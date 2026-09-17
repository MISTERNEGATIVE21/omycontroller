#!/usr/bin/env python3
"""Quatro — scripts/triggers.py

DualSense adaptive-trigger control through the controller's hidraw node.
Encodes the public DualSense output-report format (report 0x02 on USB) to
set the left/right adaptive-trigger effect mode. Wired (USB) only — over
Bluetooth the same effect needs report 0x31 with a CRC trailer, which the
kernel driver blocks from user space on stock hid-playstation.

Usage:
  triggers.py <hidraw-node> <left-mode> <right-mode>

Modes (matched by the standard adaptive-trigger vocabulary):
  off       no effect            (0x05)
  weak      light continuous     (0x02, small force)
  medium    continuous resistance (0x02, medium force)
  strong    heavy continuous     (0x02, large force)
  rigid     rigid section        (0x06)
  pulse     pulsing feedback     (0x23 / 0x26 family -> 0x26)

Examples:
  triggers.py /dev/hidraw4 strong off
  triggers.py /dev/hidraw4 medium medium

Exit codes: 0 ok, 3 unsupported device, 1 usage/IO error.
"""

import os
import re
import struct
import sys

MODES = {
    "off": ("off", 0),
    "weak": ("continuous", 0x20),
    "medium": ("continuous", 0x80),
    "strong": ("continuous", 0xE0),
    "rigid": ("rigid", 0),
    "pulse": ("pulse", 0),
}

EFFECT_OFF = 0x05
EFFECT_CONTINUOUS = 0x02
EFFECT_RIGID = 0x06
EFFECT_PULSE = 0x26


def fail(msg: str, code: int = 1) -> None:
    sys.stderr.write("triggers: " + msg + "\n")
    sys.exit(code)


def find_hidraw(vendor: str = "054c", product_prefixes=("0ce6", "0e5f")) -> str:
    """Locate the DualSense hidraw node by scanning sysfs.

    0ce6 = DualSense, 0e5f = DualSense Edge. hid-playstation binds these,
    and each gets a hidraw child under its HID device directory.
    """
    base = "/sys/bus/hid/devices"
    try:
        devices = sorted(os.listdir(base))
    except OSError:
        devices = []
    for hid_dir in devices:
        parts = hid_dir.lower().split(":")
        if len(parts) < 3 or parts[0] != vendor:
            continue
        if parts[2][:4] not in product_prefixes:
            continue
        dev_root = os.path.join(base, hid_dir)
        try:
            children = os.listdir(dev_root)
        except OSError:
            continue
        for entry in children:
            if not entry.startswith("hidraw:"):
                continue
            raw_dir = os.path.join(dev_root, entry, "hidraw")
            try:
                raw_name = os.listdir(raw_dir)[0]
            except (OSError, IndexError):
                continue
            return os.path.join("/dev", raw_name)
    fail("no DualSense hidraw device found (connect over USB)", 3)


def encode_trigger(mode: str, force: int) -> bytes:
    """5-byte trigger block for the left or right adaptive trigger."""
    if mode == "continuous":
        return struct.pack("<BBHHH", EFFECT_CONTINUOUS, 0, force, 0, 0)
    if mode == "rigid":
        return struct.pack("<BBHHH", EFFECT_RIGID, 0, 0, 0, 0)
    if mode == "pulse":
        return struct.pack("<BBHHH", EFFECT_PULSE, 0, 0x0064, 0x0032, 0)
    return struct.pack("<BBHHH", EFFECT_OFF, 0, 0, 0, 0)


def build_report(left: str, right: str) -> bytes:
    """DualSense USB output report 0x02 with only trigger bytes touched."""
    lmode, lforce = MODES.get(left, ("off", 0))
    rmode, rforce = MODES.get(right, ("off", 0))
    report = bytearray(63)
    report[0] = 0x02  # report id
    # bytes 1-3 rumble (leave 0: does not clobber rumble motor state because
    # magnitude 0 keeps the current settings on hid-playstation)
    report[4] = 0x20   # enable adaptive triggers (bit 5) — triggers only
    report[5] = 0x20
    report[10:15] = encode_trigger(lmode, lforce)   # left trigger block
    report[15:20] = encode_trigger(rmode, rforce)   # right trigger block
    return bytes(report)


def main() -> None:
    if len(sys.argv) < 4:
        fail("usage: triggers.py <hidraw-node|auto> <left-mode> <right-mode>")
    node = sys.argv[1]
    left = sys.argv[2].lower()
    right = sys.argv[3].lower()
    if left not in MODES or right not in MODES:
        fail("modes must be one of: " + " ".join(sorted(MODES)))

    if node in ("auto", "", None):
        node = find_hidraw()
    elif not re.match(r"^/dev/hidraw\d+$", node):
        fail("hidraw node must look like /dev/hidrawN or 'auto'")

    try:
        fd = os.open(node, os.O_WRONLY)
    except OSError as exc:
        fail("cannot open %s (%s)" % (node, exc))

    try:
        os.write(fd, build_report(left, right))
    except OSError as exc:
        fail("write to %s failed (%s)" % (node, exc))
    finally:
        os.close(fd)

    sys.exit(0)


if __name__ == "__main__":
    main()
