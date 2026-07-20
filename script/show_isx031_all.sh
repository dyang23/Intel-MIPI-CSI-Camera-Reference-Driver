#!/bin/bash
# Launch icamerasrc + glimagesink for every ISX031 discovered on the system,
# so all cameras behind the MAX96724 show live windows at the same time.
#
# Ctrl+C stops all pipelines (they run as background jobs; `wait` blocks until
# the user interrupts, then a SIGINT trap kills them together).
#
# Usage: bash script/show_isx031_all.sh [N]
#   N: number of cameras to open (default: auto-detect from icamerasrc)

set -e

# ---- one-shot permission fixes (safe to re-run) ---------------------------
# The camera HAL, GStreamer plugin, and /etc/camera are shipped 0750 root:root;
# fix them so non-root users can access icamerasrc without sudo.
NEED_SUDO=0
[ -r /usr/lib/gstreamer-1.0/libgsticamerasrc.so ] || NEED_SUDO=1
[ -r /usr/lib/libgsticamerainterface-1.0.so.1 ]   || NEED_SUDO=1
[ -r /usr/lib/libcamhal/plugins/ipu75xa.so ]       || NEED_SUDO=1
[ -x /etc/camera ]                                  || NEED_SUDO=1
[ -O "$HOME/.cache/gstreamer-1.0" ] || [ ! -e "$HOME/.cache/gstreamer-1.0" ] || NEED_SUDO=1

if [ "$NEED_SUDO" = 1 ]; then
    echo "Fixing camera HAL / GStreamer permissions (sudo)..."
    sudo chmod o+rx /usr/lib/gstreamer-1.0/libgsticamerasrc.so
    sudo chmod o+rx /usr/lib/libgsticamerainterface-1.0.so.1 \
                    /usr/lib/libgsticamerainterface-1.0.so.1.0.0 \
                    /usr/lib/libgsticamerainterface-1.0.so 2>/dev/null || true
    sudo find /usr/lib/libcamhal -type f -exec chmod o+rx {} \;
    sudo find /usr/lib/libcamhal -type d -exec chmod o+rx {} \;
    sudo chmod o+rx /etc/camera
    sudo rm -rf "$HOME/.cache/gstreamer-1.0"
fi

# ---- runtime env (mirrors the reference user-space GMSL doc) --------------
unset XDG_RUNTIME_DIR
export DISPLAY=:0
xhost + >/dev/null 2>&1 || true
export GST_PLUGIN_PATH=/usr/lib/gstreamer-1.0
export LIBVA_DRIVER_NAME=iHD
export GST_GL_API=gles2
export GST_GL_PLATFORM=egl
export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig
export LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/usr/lib64:/usr/lib/x86_64-linux-gnu
export logSink=terminal

# ---- discover cameras -----------------------------------------------------
if [ -n "$1" ]; then
    N=$1
else
    # Enumerate device-name values that icamerasrc advertises for isx031-*.
    N=$(gst-inspect-1.0 icamerasrc 2>/dev/null \
        | grep -oE 'isx031-[0-9]+' | sort -u | wc -l)
    [ "$N" -gt 0 ] || N=3   # fall back to 3 (S36 x2 + SHW3H x1)
fi
echo "Opening ${N} ISX031 camera(s)..."

# ---- kill children on Ctrl+C ---------------------------------------------
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; wait 2>/dev/null || true; }
trap cleanup INT TERM

# ---- launch one pipeline per camera --------------------------------------
for n in $(seq 1 "$N"); do
    gst-launch-1.0 icamerasrc num-buffers=-1 num-vc=1 scene-mode=normal \
        device-name=isx031-"$n" printfps=true io-mode=dma_mode \
        ! 'video/x-raw(memory:DMABuf),drm-format=UYVY,width=1920,height=1536' \
        ! glimagesink sync=false &
    PIDS+=("$!")
done

wait
