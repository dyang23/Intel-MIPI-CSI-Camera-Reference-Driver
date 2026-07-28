#!/bin/bash
#
# capture_boot_trace.sh
#
# Run this as the VERY FIRST action after reboot (text mode), before any
# camera app. The kernel was booted with:
#   trace_event=regmap:regmap_reg_read,regmap:regmap_reg_write,regmap:regmap_hw_read_start
#   trace_buf_size=128M
# so the ftrace ring buffer already holds every serdes register access made
# during boot bring-up - including the moment the serializer reverse channel
# dies. This script freezes tracing and extracts the transition.

set -u
TR=/sys/kernel/debug/tracing
SER=/sys/kernel/debug/regmap/i2c-INTC1138:00
OUT=/tmp/boot_trace
mkdir -p "$OUT"
[ "$(id -u)" -ne 0 ] && { echo "run with sudo"; exit 1; }

# 1) FREEZE first so nothing overwrites the boot events.
echo 0 > "$TR/tracing_on" 2>/dev/null

echo "== trace armed at boot? =="
echo "  reg_read event enabled : $(cat "$TR/events/regmap/regmap_reg_read/enable" 2>/dev/null)"
echo "  buffer_size_kb         : $(cat "$TR/buffer_size_kb" 2>/dev/null)"
head -3 "$TR/trace" | sed -n 's/#.*entries-in-buffer/entries/p'

echo "== serializer state now =="
echo "  ser 0x00 : $(head -c 12 "$SER/registers" 2>/dev/null)"
echo "  link 0x1A: $(i2ctransfer -f -y 0 w2@0x27 0x00 0x1a r1 2>&1)  (bit3=locked)"

cp "$TR/trace" "$OUT/full_trace.txt"
echo "  full trace: $(wc -l < "$OUT/full_trace.txt") lines -> $OUT/full_trace.txt"

# 2) Keep only the two serdes chips, in order.
grep -E "i2c-INTC1138:00|i2c-INTC1139:00" "$OUT/full_trace.txt" > "$OUT/serdes.txt"
echo "  serdes-chip events: $(wc -l < "$OUT/serdes.txt")  (1139=deser, 1138=serializer) -> $OUT/serdes.txt"
echo

echo "== last 6 SUCCESSFUL serializer (INTC1138) reg accesses =="
grep -E "regmap_reg_(read|write): i2c-INTC1138" "$OUT/serdes.txt" | tail -6
echo

echo "== transition: 60 serdes ops around the LAST successful serializer access =="
# line (within serdes.txt) of the last successful serializer reg read/write
LN=$(grep -nE "regmap_reg_(read|write): i2c-INTC1138" "$OUT/serdes.txt" | tail -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  START=$((LN-15)); [ "$START" -lt 1 ] && START=1
  sed -n "${START},$((LN+45))p" "$OUT/serdes.txt"
else
  echo "  (no successful serializer access found at all - reverse channel never came up)"
  echo "  showing first 40 serdes ops:"; head -40 "$OUT/serdes.txt"
fi
echo
echo "Send me $OUT/serdes.txt (or the block above). Re-arm tracing with:"
echo "  echo 1 | sudo tee $TR/tracing_on"
