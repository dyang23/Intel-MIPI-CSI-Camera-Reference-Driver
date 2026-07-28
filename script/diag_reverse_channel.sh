#!/bin/bash
#
# diag_reverse_channel.sh
#
# Run this ONCE, right after a fresh reboot, BEFORE any streaming attempt.
# It captures the exact operation that kills the GMSL reverse control channel
# to the serializer (max96717) during the first enable_streams.
#
# Findings so far (black-box / nodka board, s36-DongYang branch):
#   - deserializer(0x27), serializer(INTC1138@i2c-7 0x40) and isx031 all probe OK
#     at boot -> reverse control channel is UP at probe time.
#   - the serializer stays reachable and STABLE while idle (verified 30s).
#   - the FIRST real enable_streams kills the reverse channel: link stays LOCKED
#     (0x1A bit3=1) but the serializer stops ACKing (-121 / EREMOTEIO), and it
#     does NOT recover until the deserializer is fully re-initialised.
#   - removing the per-i2c-mux-select one-shot reset (select_links patch) did
#     NOT fix it -> there is a SECOND mechanism in the stream path.
#
# This script samples serializer reachability (via the driver's own regmap
# debugfs, the reliable path) and full regmap ftrace across the first stream,
# so we can see the last successful serializer access and the first failing one.

set -u
DES=/sys/kernel/debug/regmap/i2c-INTC1139:00     # deserializer max96724
SER=/sys/kernel/debug/regmap/i2c-INTC1138:00     # serializer max96717
TR=/sys/kernel/debug/tracing
OUT=/tmp/revchan_diag
mkdir -p "$OUT"

if [ "$(id -u)" -ne 0 ]; then echo "run with sudo"; exit 1; fi

ser_id() { head -c 16 "$SER/registers" 2>/dev/null | tr '\n' ' '; }

echo "== STEP 0: state right after boot (no stream yet) =="
echo "  link lock 0x1A : $(i2ctransfer -f -y 0 w2@0x27 0x00 0x1a r1 2>&1)"
S0="$(ser_id)"
echo "  serializer 0x00: $S0   <- should be readable (e.g. 0000: 88)"
case "$S0" in
  *XX*)
    echo
    echo "!! ABORT: serializer already DEAD before this script streamed anything."
    echo "!! That means a stream was attempted since boot and already killed the"
    echo "!! reverse channel. This run cannot capture the KILL, only the corpse."
    echo "!!"
    echo "!! Please: sudo reboot, then run THIS script as the very FIRST action"
    echo "!! (do NOT run v4l2-ctl / any camera app before it)."
    exit 2 ;;
esac
echo "  (serializer is ALIVE - good, we can capture the kill)"
echo

echo "== STEP 1: program media graph =="
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SD/acpi/mc-setup.sh" >"$OUT/mc-setup.log" 2>&1
echo "  mc-setup exit=$?  (see $OUT/mc-setup.log)"
echo "  serializer after mc-setup: $(ser_id)"
echo

echo "== STEP 2: arm regmap ftrace =="
echo 0 > "$TR/tracing_on"; : > "$TR/trace"
echo 1 > "$TR/events/regmap/enable"
echo 1 > "$TR/tracing_on"

echo "== STEP 3: first stream (this is expected to fail with -121) =="
timeout 6 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=2 2>&1 | tail -2

echo 0 > "$TR/tracing_on"
cp "$TR/trace" "$OUT/trace.txt"
echo
echo "== STEP 4: serializer state immediately after the failed stream =="
echo "  link lock 0x1A : $(i2ctransfer -f -y 0 w2@0x27 0x00 0x1a r1 2>&1)"
echo "  serializer 0x00: $(ser_id)   <- if now 'XX' the reverse channel died"
echo

echo "== STEP 5: the transition point in the trace =="
# Keep only real reg read/write events on the two serdes chips, in order.
grep -E "regmap_reg_(read|write): (i2c-INTC1139|i2c-INTC1138)" "$OUT/trace.txt" \
    | sed -E 's/.*: (regmap_reg_[rw]+): (i2c-INTC113[89]:00) (.*)/\1 \2 \3/' \
    > "$OUT/serdes_ops.txt"
# A successful serializer read/write shows a regmap_reg_* line; a FAILED read
# still emits hw_read_start/done but NO regmap_reg_read (regmap returned -EIO).
# So count how many serializer ops actually succeeded:
SER_OK=$(grep -c "INTC1138" "$OUT/serdes_ops.txt")
SER_TRIED=$(grep -c "regmap_hw_read_start: i2c-INTC1138" "$OUT/trace.txt")
echo "  serializer reads/writes attempted: $SER_TRIED, succeeded (got a value): $SER_OK"
echo
echo "  --- full ordered serdes-chip op list (des=1139 / ser=1138) ---"
cat -n "$OUT/serdes_ops.txt"
echo
echo "  --- the FIRST failed serializer access + 12 serdes ops before it ---"
FL=$(grep -nE "INTC1138" "$OUT/trace.txt" | head -1 | cut -d: -f1)
if [ -n "$FL" ]; then
  awk -v L="$FL" 'NR>=L-40 && NR<=L+2 && /regmap_(reg|hw)_/' "$OUT/trace.txt" \
    | grep -E "INTC1139|INTC1138" | tail -15
fi
echo
echo "  --- i2c_designware TX_ABRT_SOURCE(0x80)/INTR_STAT(0x34) around the failure ---"
grep -nE "i2c_designware.*reg=(80|34) " "$OUT/trace.txt" | tail -10
echo
echo "Full trace: $OUT/trace.txt  |  ordered serdes ops: $OUT/serdes_ops.txt"
echo "(reg=18 one-shot reset, reg=6 LINK_EN, reg=3/reg=e remote-CC, INTC1138=serializer)"
