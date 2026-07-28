#!/usr/bin/env python3
"""Measure inter-camera shutter phase alignment from V4L2 buffer timestamps.

This is the software stand-in for probing FSIN with an oscilloscope: instead of
looking at the pulse, it looks at the thing the pulse is supposed to achieve --
that the Nth frame of every camera is captured at the same instant.

Each capture thread streams from one /dev/videoN and records the kernel
timestamp of every dequeued buffer.  Frames are then matched by capture index
across devices and the spread max(ts) - min(ts) is reported.

    free-running (no FSYNC):  spread is uniform in [0, 1/fps], mean ~= 1/(2*fps)
    hardware synchronised:    spread collapses to the tens-of-microseconds range

Usage:
    python3 script/fsync_phase_check.py                     # /dev/video0..3, 300 frames
    python3 script/fsync_phase_check.py -d /dev/video0 /dev/video1 -n 600
    python3 script/fsync_phase_check.py --json baseline.json

No third-party modules; talks to V4L2 through ctypes so it can run on a bare
target.  Requires read/write access to the video nodes (video group).
"""

import argparse
import ctypes
import fcntl
import json
import os
import statistics
import sys
import threading

# --- V4L2 ABI ---------------------------------------------------------------

V4L2_BUF_TYPE_VIDEO_CAPTURE = 1
V4L2_MEMORY_MMAP = 1
V4L2_BUF_FLAG_TIMESTAMP_MASK = 0x0000E000
V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC = 0x00002000
V4L2_BUF_FLAG_ERROR = 0x00000040


class Timeval(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]


class Timecode(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("frames", ctypes.c_uint8),
        ("seconds", ctypes.c_uint8),
        ("minutes", ctypes.c_uint8),
        ("hours", ctypes.c_uint8),
        ("userbits", ctypes.c_uint8 * 4),
    ]


class RequestBuffers(ctypes.Structure):
    _fields_ = [
        ("count", ctypes.c_uint32),
        ("type", ctypes.c_uint32),
        ("memory", ctypes.c_uint32),
        ("capabilities", ctypes.c_uint32),
        ("flags", ctypes.c_uint8),
        ("reserved", ctypes.c_uint8 * 3),
    ]


class _BufferUnion(ctypes.Union):
    _fields_ = [
        ("offset", ctypes.c_uint32),
        ("userptr", ctypes.c_ulong),
        ("planes", ctypes.c_void_p),
        ("fd", ctypes.c_int32),
    ]


class Buffer(ctypes.Structure):
    _fields_ = [
        ("index", ctypes.c_uint32),
        ("type", ctypes.c_uint32),
        ("bytesused", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("field", ctypes.c_uint32),
        ("timestamp", Timeval),
        ("timecode", Timecode),
        ("sequence", ctypes.c_uint32),
        ("memory", ctypes.c_uint32),
        ("m", _BufferUnion),
        ("length", ctypes.c_uint32),
        ("reserved2", ctypes.c_uint32),
        ("request_fd", ctypes.c_int32),
    ]


def _ioc(direction, size):
    return (direction << 30) | (size << 16) | (ord("V") << 8)


_IOWR, _IOW = 3, 1
VIDIOC_REQBUFS = _ioc(_IOWR, ctypes.sizeof(RequestBuffers)) | 8
VIDIOC_QBUF = _ioc(_IOWR, ctypes.sizeof(Buffer)) | 15
VIDIOC_DQBUF = _ioc(_IOWR, ctypes.sizeof(Buffer)) | 17
VIDIOC_STREAMON = _ioc(_IOW, ctypes.sizeof(ctypes.c_int)) | 18
VIDIOC_STREAMOFF = _ioc(_IOW, ctypes.sizeof(ctypes.c_int)) | 19

NBUFS = 6


# --- capture ----------------------------------------------------------------


class Capture:
    """Streams one video node and records a timestamp per frame."""

    def __init__(self, path, count):
        self.path = path
        self.count = count
        self.stamps = []        # CLOCK_MONOTONIC nanoseconds
        self.sequences = []
        self.error = None
        self.clock = None

    def run(self, start_barrier):
        try:
            self._run(start_barrier)
        except Exception as exc:              # noqa: BLE001 - reported per device
            self.error = f"{type(exc).__name__}: {exc}"
            # Do not leave peers waiting on a barrier we will never reach.
            try:
                start_barrier.abort()
            except Exception:                 # noqa: BLE001
                pass

    def _run(self, start_barrier):
        fd = os.open(self.path, os.O_RDWR)
        try:
            req = RequestBuffers(count=NBUFS, type=V4L2_BUF_TYPE_VIDEO_CAPTURE,
                                 memory=V4L2_MEMORY_MMAP)
            fcntl.ioctl(fd, VIDIOC_REQBUFS, req)
            if req.count < 2:
                raise RuntimeError(f"driver granted only {req.count} buffers")

            for i in range(req.count):
                buf = Buffer(index=i, type=V4L2_BUF_TYPE_VIDEO_CAPTURE,
                             memory=V4L2_MEMORY_MMAP)
                fcntl.ioctl(fd, VIDIOC_QBUF, buf)

            # Line every thread up so all four STREAMONs land together; a
            # staggered start would bias the very first frames.
            start_barrier.wait()

            arg = ctypes.c_int(V4L2_BUF_TYPE_VIDEO_CAPTURE)
            fcntl.ioctl(fd, VIDIOC_STREAMON, arg)
            try:
                for _ in range(self.count):
                    buf = Buffer(type=V4L2_BUF_TYPE_VIDEO_CAPTURE,
                                 memory=V4L2_MEMORY_MMAP)
                    fcntl.ioctl(fd, VIDIOC_DQBUF, buf)
                    if self.clock is None:
                        self.clock = buf.flags & V4L2_BUF_FLAG_TIMESTAMP_MASK
                    if not buf.flags & V4L2_BUF_FLAG_ERROR:
                        self.stamps.append(buf.timestamp.tv_sec * 1_000_000_000
                                           + buf.timestamp.tv_usec * 1000)
                        self.sequences.append(buf.sequence)
                    fcntl.ioctl(fd, VIDIOC_QBUF, buf)
            finally:
                fcntl.ioctl(fd, VIDIOC_STREAMOFF, ctypes.c_int(
                    V4L2_BUF_TYPE_VIDEO_CAPTURE))
        finally:
            os.close(fd)


# --- analysis ---------------------------------------------------------------


def fps_of(stamps):
    if len(stamps) < 2:
        return None
    span = (stamps[-1] - stamps[0]) / 1e9
    return (len(stamps) - 1) / span if span > 0 else None


def wrap_phase(delta_ms, period_ms):
    """Fold a raw timestamp delta into the [-period/2, +period/2] shutter phase.

    Devices rarely deliver their first frame on the same tick, so a raw delta
    carries an arbitrary whole number of frame periods on top of the quantity we
    actually care about.  Only the remainder says whether the shutters fire
    together.
    """
    phase = delta_ms % period_ms
    if phase > period_ms / 2:
        phase -= period_ms
    return phase


def analyse(caps, warmup):
    """Report both the raw cross-device spread and the folded shutter phase."""
    usable = [c for c in caps if not c.error and len(c.stamps) > warmup]
    if len(usable) < 2:
        return None

    # Drop the warm-up frames: the first few are skewed by staggered STREAMON
    # and by the sensor settling, neither of which reflects shutter phase.
    series = [c.stamps[warmup:] for c in usable]
    n = min(len(s) for s in series)
    spreads = [(max(s[i] for s in series) - min(s[i] for s in series)) / 1e6
               for i in range(n)]

    rates = [r for r in (fps_of(c.stamps) for c in usable) if r]
    period_ms = 1000.0 / statistics.mean(rates) if rates else 1000.0 / 30

    # Phase of every device against the first, folded into one frame period.
    ref = series[0]
    phases = {}
    for cap, s in zip(usable, series):
        vals = [wrap_phase((s[i] - ref[i]) / 1e6, period_ms) for i in range(n)]
        phases[cap.path] = {
            "mean_ms": statistics.mean(vals),
            "stdev_ms": statistics.stdev(vals) if len(vals) > 1 else 0.0,
            "whole_frames_offset": round(((s[0] - ref[0]) / 1e6) / period_ms),
        }

    # Worst-case shutter misalignment across the array.
    means = [p["mean_ms"] for p in phases.values()]
    phase_spread = max(means) - min(means)

    return {
        "devices": [c.path for c in usable],
        "frames_compared": n,
        "frame_period_ms": period_ms,
        "raw_spread_ms": {
            "mean": statistics.mean(spreads),
            "median": statistics.median(spreads),
            "min": min(spreads),
            "max": max(spreads),
            "stdev": statistics.stdev(spreads) if len(spreads) > 1 else 0.0,
        },
        "shutter_phase": phases,
        "shutter_phase_spread_ms": phase_spread,
        "per_device_fps": {c.path: fps_of(c.stamps) for c in usable},
    }


def verdict(result):
    """Judge on the folded shutter phase, not on the raw delta.

    The raw delta includes whole frame periods from a staggered stream start,
    which says nothing about whether the shutters fire together.
    """
    period_ms = result["frame_period_ms"]
    spread = result["shutter_phase_spread_ms"]
    if spread < period_ms * 0.02:
        return "SYNCHRONISED", f"shutter phase spread {spread:.3f} ms < 2% of the {period_ms:.2f} ms frame period"
    if spread > period_ms * 0.05:
        return "NOT SYNCHRONISED", f"shutter phase spread {spread:.2f} ms = {100 * spread / period_ms:.0f}% of the {period_ms:.2f} ms frame period"
    return "INCONCLUSIVE", f"shutter phase spread {spread:.3f} ms sits between the clear-sync and free-running bands"


# --- main -------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-d", "--devices", nargs="+",
                    default=["/dev/video0", "/dev/video1", "/dev/video2", "/dev/video3"])
    ap.add_argument("-n", "--frames", type=int, default=300)
    ap.add_argument("--warmup", type=int, default=15,
                    help="frames discarded before analysis (default: 15)")
    ap.add_argument("--json", metavar="FILE", help="also write the report as JSON")
    args = ap.parse_args()

    missing = [d for d in args.devices if not os.path.exists(d)]
    if missing:
        sys.exit(f"no such device: {', '.join(missing)}")
    if args.frames <= args.warmup:
        sys.exit(f"--frames ({args.frames}) must exceed --warmup ({args.warmup})")

    print(f"capturing {args.frames} frames from {len(args.devices)} devices "
          f"({', '.join(args.devices)}) ...")

    caps = [Capture(d, args.frames) for d in args.devices]
    barrier = threading.Barrier(len(caps))
    threads = [threading.Thread(target=c.run, args=(barrier,), daemon=True) for c in caps]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    print()
    for c in caps:
        if c.error:
            print(f"  {c.path}: FAILED  {c.error}")
            continue
        rate = fps_of(c.stamps)
        clock = ("monotonic" if c.clock == V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC
                 else f"flags=0x{c.clock:x}" if c.clock is not None else "unknown")
        dropped = args.frames - len(c.stamps)
        print(f"  {c.path}: {len(c.stamps):4d} frames  "
              f"{rate:6.2f} fps  clock={clock}"
              + (f"  ({dropped} dropped)" if dropped else ""))

    result = analyse(caps, args.warmup)
    if not result:
        sys.exit("\nneed at least two devices to have captured successfully")

    period = result["frame_period_ms"]
    s = result["raw_spread_ms"]

    print(f"\nraw timestamp spread over {result['frames_compared']} matched frames "
          f"(includes whole-frame start offsets):")
    print(f"  mean {s['mean']:8.3f} ms   min {s['min']:8.3f}   "
          f"max {s['max']:8.3f}   stdev {s['stdev']:.4f}")

    print(f"\nshutter phase vs {result['devices'][0]}, folded into the "
          f"{period:.2f} ms frame period:")
    for path, p in result["shutter_phase"].items():
        print(f"  {path}: {p['mean_ms']:+8.3f} ms  "
              f"(jitter {p['stdev_ms']:.4f} ms, "
              f"{p['whole_frames_offset']:+d} whole frames)")

    state, why = verdict(result)
    print(f"\n  worst-case shutter misalignment: "
          f"{result['shutter_phase_spread_ms']:.3f} ms")
    print(f"  => {state}: {why}")

    if args.json:
        result["verdict"] = state
        rates = [r for r in result["per_device_fps"].values() if r]
        result["mean_fps"] = statistics.mean(rates) if rates else None
        with open(args.json, "w") as fh:
            json.dump(result, fh, indent=2)
        print(f"\nwrote {args.json}")


if __name__ == "__main__":
    main()
