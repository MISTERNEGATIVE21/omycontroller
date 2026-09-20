#!/usr/bin/env python3
"""Quatro — scripts/rumble.py

One-shot force-feedback rumble test for any controller that exposes FF_RUMBLE
through evdev (xpadneo, xpad, hid-playstation, hid-nintendo, 8BitDo, ...).

Usage:
  rumble.py <event-node> <weak 0-65535> <strong 0-65535> <duration-ms> [delay-ms]

Examples:
  rumble.py /dev/input/event22 20000 0 300        # weak only
  rumble.py /dev/input/event22 0 40000 400        # strong only
  rumble.py /dev/input/event22 30000 30000 500    # both

Requires python-evdev (Arch: pacman -S python-evdev). Exits 0 on success,
3 when python-evdev is missing, 1 on any other failure. Service.qml reads
stderr for the actionable message.
"""

import os
import re
import stat
import sys
import time


def fail(msg: str, code: int = 1) -> "None":
    sys.stderr.write("rumble: " + msg + "\n")
    sys.exit(code)


def main() -> None:
    if len(sys.argv) < 5:
        fail("usage: rumble.py <event-node> <weak> <strong> <ms> [delay-ms]")
    node = sys.argv[1]

    if not re.match(r"^/dev/input/event\d+$", node):
        fail(f"invalid device node: {node} must match /dev/input/eventNN", 2)

    real_node = os.path.realpath(node)
    if not real_node.startswith("/dev/input/event"):
        fail(f"path traversal rejected: {real_node}", 2)

    try:
        st = os.stat(real_node)
        if not stat.S_ISCHR(st.st_mode):
            fail(f"device node {real_node} is not a character device", 2)
    except OSError as exc:
        fail(f"cannot stat {real_node}: {exc}", 1)

    try:
        weak = max(0, min(65535, int(sys.argv[2])))
        strong = max(0, min(65535, int(sys.argv[3])))
        ms = max(30, min(5000, int(sys.argv[4])))
        delay = max(0, min(1000, int(sys.argv[5]) if len(sys.argv) > 5 else 0))
    except ValueError:
        fail("arguments must be integers")

    try:
        from evdev import ecodes, ff  # noqa: PLC0415 — lazy import
    except ImportError:
        fail("python-evdev is not installed — run: sudo pacman -S --needed python-evdev", 3)

    try:
        # Write the effect through a tiny uinput hole punched for the same
        # device is not possible; effects must be uploaded to the physical
        # device, which needs write access to it (user must be in `input`).
        from evdev import InputDevice  # noqa: PLC0415
        dev = InputDevice(real_node)
    except (OSError, PermissionError) as exc:
        fail("cannot open %s (%s)" % (real_node, exc))

    if not hasattr(dev, "upload_effect"):
        fail("device %s does not support force feedback" % node)

    rumble = ff.Effect(
        ecodes.FF_RUMBLE,
        time_left=0,
        delay=0,
        u=ff.EffectU(
            type=ecodes.FF_RUMBLE,
            data=ff.EffectUData(
                strong_magnitude=strong,
                weak_magnitude=weak,
                delay=0,
            ),
        ),
    )

    try:
        effect_id = dev.upload_effect(rumble)
    except (OSError, PermissionError) as exc:
        fail("cannot upload effect to %s (%s) — are you in the input group?" % (node, exc))

    if delay:
        time.sleep(delay / 1000.0)

    repeat = 1
    try:
        dev.write(ecodes.EV_FF, effect_id, repeat)
    except OSError as exc:
        fail("cannot play effect on %s (%s)" % (node, exc))

    time.sleep(ms / 1000.0)
    # The effect auto-stops after its duration; nothing to clean up.
    sys.exit(0)


if __name__ == "__main__":
    main()
