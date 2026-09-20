#!/usr/bin/env python3
# Quatro — scripts/gyro.py
#
# Streams a gamepad's motion sensor (accelerometer + gyroscope) as JSON
# snapshot lines on stdout:
#
#   {"ax":-0.0981,"ay":0.1961,"az":9.6105,"gx":0.001,"gy":-0.004,"gz":0.0,"afs":8191,"gfs":2048}
#
# Values are normalized against each axis's real full scale, read from the
# kernel via EVIOCGABS — accelerometer axes are scaled by 9.80665 m/s² so
# resting Z shows ~9.81 m/s² consistent with the UI scale.
# "afs"/"gfs" report the accelerometer/gyro full scale so the UI can label
# the gauge.
#
# Which device: the motion-sensor companion node that hid-playstation,
# hid-sony and hid-nintendo expose next to the pad ("... Motion Sensors"
# / "... IMU"). scan.sh pairs it to the pad; Service.qml launches this
# script against /dev/input/eventNN.
#
# Python stdlib only — no python-evdev required. Exits quietly when the
# device disappears (pad unplugged); the service restarts it on the next
# scan that finds the node again.

import json
import os
import re
import stat
import struct
import sys
import time

EV_ABS = 0x0003
ACC_CODES = (0, 1, 2)      # ABS_X/Y/Z      accelerometer
GYR_CODES = (3, 4, 5)      # ABS_RX/RY/RZ   gyroscope
EMIT_S = 0.04              # 25 snapshots per second is plenty for a gauge

# struct input_event on this ABI (64-bit timeval, or 32-bit without
# 64-bit time_t): tv_sec, tv_usec, type, code, value.
EVENT = struct.Struct("llHHi")

# EVIOCGABS(code) = _IOR('E', 0x40 + code, struct input_absinfo)
#   _IOR(t, n, size) = 1<<30 | size<<16 | t<<8 | n
# struct input_absinfo = 6 x s32 (value, min, max, fuzz, flat, resolution)
def abs_max(fd: int, code: int, default: int = 32767) -> int:
    try:
        import fcntl
        req = (1 << 30) | (24 << 16) | (0x45 << 8) | (0x40 + code)
        raw = fcntl.ioctl(fd, req, b"\x00" * 24)
        value, lo, hi = struct.unpack("iiiiii", raw)[:3]
        scale = max(abs(lo), abs(hi))
        return scale if scale > 0 else default
    except Exception:
        return default


def normalize(value: float, full_scale: float) -> float:
    v = value / float(full_scale) if full_scale else 0.0
    return max(-1.0, min(1.0, v))


GRAVITY_MSS = 9.80665


def snapshot(vals: dict[str, float], fs: dict[str, int]) -> str:
    return json.dumps({
        "ax": round(vals["ax"] * GRAVITY_MSS, 4),
        "ay": round(vals["ay"] * GRAVITY_MSS, 4),
        "az": round(vals["az"] * GRAVITY_MSS, 4),
        "gx": round(vals["gx"], 4), "gy": round(vals["gy"], 4), "gz": round(vals["gz"], 4),
        "afs": fs["ax"], "gfs": fs["gx"],
    })


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: gyro.py /dev/input/eventNN", file=sys.stderr)
        return 2

    node = sys.argv[1]
    if not re.match(r"^/dev/input/event\d+$", node):
        print(f"invalid device node: {node} must match /dev/input/eventNN", file=sys.stderr)
        return 2

    real_node = os.path.realpath(node)
    if not real_node.startswith("/dev/input/event"):
        print(f"path traversal rejected: {real_node}", file=sys.stderr)
        return 2

    try:
        st = os.stat(real_node)
        if not stat.S_ISCHR(st.st_mode):
            print(f"device node {real_node} is not a character device", file=sys.stderr)
            return 2
    except OSError as e:
        print(f"cannot stat {real_node}: {e}", file=sys.stderr)
        return 1

    try:
        fd = os.open(real_node, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as e:
        print(f"cannot open {real_node}: {e}", file=sys.stderr)
        return 1

    full = {}
    for c in ACC_CODES:
        full["ax" if c == 0 else "ay" if c == 1 else "az"] = abs_max(fd, c)
    for c in GYR_CODES:
        full["gx" if c == 3 else "gy" if c == 4 else "gz"] = abs_max(fd, c)

    key_by_code = {0: "ax", 1: "ay", 2: "az", 3: "gx", 4: "gy", 5: "gz"}
    vals = {k: 0.0 for k in key_by_code.values()}
    dirty = False
    last_emit = 0.0
    size = EVENT.size

    while True:
        try:
            data = os.read(fd, size * 32)
        except BlockingIOError:
            now = time.monotonic()
            if dirty and now - last_emit >= EMIT_S:
                sys.stdout.write(snapshot(vals, full) + "\n")
                sys.stdout.flush()
                dirty = False
                last_emit = now
            time.sleep(0.004)
            continue
        if not data:
            break  # device went away; the service will restart us later

        for off in range(0, len(data) - size + 1, size):
            _, _, etype, code, value = EVENT.unpack_from(data, off)
            if etype != EV_ABS:
                continue
            k = key_by_code.get(code)
            if k:
                vals[k] = normalize(value, full[k])
                dirty = True

        now = time.monotonic()
        if dirty and now - last_emit >= EMIT_S:
            sys.stdout.write(snapshot(vals, full) + "\n")
            sys.stdout.flush()
            dirty = False
            last_emit = now

    if dirty:
        sys.stdout.write(snapshot(vals, full) + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
