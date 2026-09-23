#!/usr/bin/env python3
# omycontroller — scripts/stream.py
#
# Standalone zero-dependency Python 3 joystick event streamer.
# Reads 8-byte struct js_event records from /dev/input/js* and prints
# header and event lines compatible with Service.qml event parser:
#
#   Joystick (Name) has 8 axes (X, Y, Z, Rz, Gas, Brake, Hat0X, Hat0Y) and 15 buttons.
#   Event: time 12345.678, type 1, number 0, value 1
#
# Exits cleanly when the device is unplugged or interrupted.

import fcntl
import os
import re
import stat
import struct
import sys
import time

# Standard Linux joydev ioctls
JSIOCGVERSION = 0x80046a01
JSIOCGAXES = 0x80016a11
JSIOCGBUTTONS = 0x80016a12
JSIOCGNAME = lambda size: 0x80006a13 + (size << 16)
JSIOCGAXMAP = 0x80406a32
JSIOCGBTNMAP = 0x80406a34

AXIS_NAMES = {
    0: "X", 1: "Y", 2: "Z", 3: "Rx", 4: "Ry", 5: "Rz",
    6: "Throttle", 7: "Rudder", 8: "Wheel", 9: "Gas", 10: "Brake",
    16: "Hat0X", 17: "Hat0Y", 18: "Hat1X", 19: "Hat1Y",
    20: "Hat2X", 21: "Hat2Y", 22: "Hat3X", 23: "Hat3Y"
}

EVENT_STRUCT = struct.Struct("IhBB")


def validate_node(node: str) -> str:
    if not re.match(r"^/dev/input/js\d+$", node):
        print(f"invalid device node: {node} must match /dev/input/jsN", file=sys.stderr)
        sys.exit(2)

    real_node = os.path.realpath(node)
    if not real_node.startswith("/dev/input/js"):
        print(f"path traversal rejected: {real_node}", file=sys.stderr)
        sys.exit(2)

    try:
        st = os.stat(real_node)
        if not stat.S_ISCHR(st.st_mode):
            print(f"device node {real_node} is not a character device", file=sys.stderr)
            sys.exit(2)
    except OSError as e:
        print(f"cannot stat {real_node}: {e}", file=sys.stderr)
        sys.exit(1)

    return real_node


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: stream.py /dev/input/jsN", file=sys.stderr)
        return 2

    real_node = validate_node(sys.argv[1])

    try:
        fd = os.open(real_node, os.O_RDONLY)
    except OSError as e:
        print(f"cannot open {real_node}: {e}", file=sys.stderr)
        return 1

    try:
        # Read device name
        buf_name = bytearray(128)
        try:
            fcntl.ioctl(fd, JSIOCGNAME(128), buf_name)
            name = buf_name.split(b"\x00")[0].decode("utf-8", "replace").strip()
        except Exception:
            name = "Gamepad"

        # Read axis count
        buf_axes = bytearray(1)
        try:
            fcntl.ioctl(fd, JSIOCGAXES, buf_axes)
            axes_count = buf_axes[0]
        except Exception:
            axes_count = 0

        # Read button count
        buf_btns = bytearray(1)
        try:
            fcntl.ioctl(fd, JSIOCGBUTTONS, buf_btns)
            btns_count = buf_btns[0]
        except Exception:
            btns_count = 0

        # Read axis map names
        ax_names = []
        if axes_count > 0:
            axmap = bytearray(64)
            try:
                fcntl.ioctl(fd, JSIOCGAXMAP, axmap)
                for i in range(axes_count):
                    code = axmap[i]
                    ax_names.append(AXIS_NAMES.get(code, f"Axis{code}"))
            except Exception:
                ax_names = [f"Axis{i}" for i in range(axes_count)]

        # Print header line for Service.qml
        axis_str = ", ".join(ax_names)
        header = f"Joystick ({name}) has {axes_count} axes ({axis_str}) and {btns_count} buttons."
        sys.stdout.write(header + "\n")
        sys.stdout.flush()

        # Read event loop
        chunk_size = EVENT_STRUCT.size * 32
        while True:
            try:
                data = os.read(fd, chunk_size)
            except OSError:
                break
            if not data:
                break  # Controller unplugged or device closed

            for off in range(0, len(data) - EVENT_STRUCT.size + 1, EVENT_STRUCT.size):
                time_ms, value, ev_type, number = EVENT_STRUCT.unpack_from(data, off)
                time_s = time_ms / 1000.0
                sys.stdout.write(
                    f"Event: time {time_s:.3f}, type {ev_type}, number {number}, value {value}\n"
                )
            sys.stdout.flush()

    finally:
        try:
            os.close(fd)
        except OSError:
            pass

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
