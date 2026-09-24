#!/usr/bin/env python3
"""Quatro — scripts/haptic_midi.py

High-precision melodic and waveform force-feedback haptic player for gamepads.
Translates musical note frequencies, retro game MIDIs, and sculpted waveforms
into acoustic vibrations using controller Linear Resonant Actuators (LRAs)
and dual ERM motors via evdev EV_FF (hid-nintendo, hid-playstation, xpadneo).

Usage:
  haptic_midi.py <event-node> <track-name> [--volume 0.0-1.0] [--repeat N]

Tracks:
  mario       - Super Mario Bros Overworld (Ground Theme)
  zelda       - The Legend of Zelda Overworld Theme
  tetris      - Tetris Type A (Korobeiniki)
  pokemon     - Pokémon Red/Blue Wild Battle Intro
  coin        - Nintendo 2-tone Coin jingle
  oneup       - Mario 6-note 1-Up fanfare
  pulse       - Crisp staccato haptic tick series
  heartbeat   - Dual-pulse cardiac rhythm
  ramp        - Progressive power ramp (20% -> 100%)
  sine        - Frequency modulated sweep (120 Hz -> 320 Hz)
  earthquake  - Heavy low-frequency seismic wave
  engine      - Throttle engine acceleration pattern
"""

import math
import os
import re
import signal
import stat
import sys
import time

TRACKS = {
    # Note format: (frequency_hz, duration_ms, is_strong, relative_gain)
    "mario": [
        # Intro fanfare
        (660, 110, False, 1.0),
        (0, 50, False, 0.0),
        (660, 110, False, 1.0),
        (0, 120, False, 0.0),
        (660, 110, False, 1.0),
        (0, 120, False, 0.0),
        (523, 110, False, 0.9),
        (660, 130, False, 1.0),
        (0, 100, False, 0.0),
        (784, 200, False, 1.0),
        (0, 200, False, 0.0),
        (392, 220, True, 1.0),
        (0, 250, False, 0.0),
        # Main theme groove
        (523, 160, True, 0.9),
        (0, 120, False, 0.0),
        (392, 160, True, 0.9),
        (0, 120, False, 0.0),
        (330, 160, True, 0.9),
        (0, 120, False, 0.0),
        (440, 140, False, 0.9),
        (0, 80, False, 0.0),
        (494, 140, False, 0.9),
        (0, 80, False, 0.0),
        (466, 120, False, 0.8),
        (0, 60, False, 0.0),
        (440, 180, False, 0.9),
        (0, 100, False, 0.0),
        (392, 140, True, 0.9),
        (660, 140, False, 1.0),
        (784, 160, False, 1.0),
        (880, 160, False, 1.0),
        (698, 120, False, 0.9),
        (784, 140, False, 1.0),
        (660, 160, False, 1.0),
        (523, 140, True, 0.9),
        (587, 140, False, 0.9),
        (494, 220, False, 0.9),
    ],
    "zelda": [
        (466, 200, True, 0.9),   # Bb4
        (0, 50, False, 0.0),
        (349, 140, True, 0.8),   # F4
        (0, 50, False, 0.0),
        (466, 180, True, 0.9),   # Bb4
        (0, 50, False, 0.0),
        (523, 140, False, 0.85), # C5
        (587, 140, False, 0.9),  # D5
        (622, 140, False, 0.9),  # Eb5
        (698, 380, False, 1.0),  # F5
        (0, 100, False, 0.0),
        (698, 120, False, 0.9),
        (698, 120, False, 0.9),
        (740, 140, False, 0.9),  # F#5
        (831, 140, False, 0.9),  # G#5
        (932, 400, False, 1.0),  # Bb5
    ],
    "tetris": [
        (659, 180, False, 1.0),  # E5
        (494, 110, False, 0.85), # B4
        (523, 110, False, 0.85), # C5
        (587, 180, False, 0.9),  # D5
        (523, 110, False, 0.85), # C5
        (494, 110, False, 0.85), # B4
        (440, 220, True, 0.9),   # A4
        (0, 50, False, 0.0),
        (440, 110, True, 0.8),
        (523, 140, False, 0.85),
        (659, 200, False, 1.0),
        (587, 140, False, 0.9),
        (523, 140, False, 0.85),
        (494, 250, False, 0.9),
    ],
    "pokemon": [
        (392, 90, True, 0.85),
        (370, 90, True, 0.8),
        (392, 90, True, 0.85),
        (370, 90, True, 0.8),
        (392, 110, True, 0.9),
        (392, 90, True, 0.85),
        (370, 90, True, 0.8),
        (370, 90, True, 0.8),
        (392, 120, True, 0.9),
        (440, 120, False, 0.9),
        (494, 120, False, 0.95),
        (523, 140, False, 1.0),
        (587, 240, False, 1.0),
    ],
    "coin": [
        (988, 80, False, 0.85),  # B5
        (1319, 360, False, 1.0), # E6
    ],
    "oneup": [
        (330, 90, True, 0.8),    # E4
        (392, 90, True, 0.85),   # G4
        (659, 90, False, 0.9),   # E5
        (523, 90, False, 0.9),   # C5
        (587, 90, False, 0.95),  # D5
        (784, 280, False, 1.0),  # G5
    ],
    "pulse": [
        (400, 70, False, 0.9),
        (0, 70, False, 0.0),
        (400, 70, False, 0.9),
        (0, 70, False, 0.0),
        (400, 70, False, 0.9),
        (0, 70, False, 0.0),
        (400, 110, False, 1.0),
    ],
    "heartbeat": [
        (140, 90, True, 0.65),
        (0, 70, False, 0.0),
        (180, 180, True, 1.0),
        (0, 350, False, 0.0),
        (140, 90, True, 0.65),
        (0, 70, False, 0.0),
        (180, 180, True, 1.0),
    ],
    "ramp": [
        (220, 130, True, 0.25),
        (260, 130, True, 0.50),
        (320, 130, False, 0.75),
        (440, 260, False, 1.00),
    ],
    "sine": [
        (120, 80, True, 0.5),
        (160, 80, True, 0.65),
        (200, 80, True, 0.8),
        (250, 80, False, 0.9),
        (300, 100, False, 1.0),
        (250, 80, False, 0.9),
        (200, 80, True, 0.8),
        (160, 80, True, 0.65),
        (120, 100, True, 0.5),
    ],
    "earthquake": [
        (80, 180, True, 1.0),
        (90, 200, True, 0.9),
        (75, 220, True, 1.0),
        (65, 300, True, 0.85),
    ],
    "engine": [
        (100, 90, True, 0.35),
        (130, 90, True, 0.50),
        (170, 90, True, 0.68),
        (220, 100, False, 0.82),
        (290, 120, False, 0.95),
        (380, 280, False, 1.00),
    ],
}


def fail(msg: str, code: int = 1) -> None:
    sys.stderr.write("haptic_midi: " + msg + "\n")
    sys.exit(code)


def main() -> None:
    if len(sys.argv) < 3:
        fail("usage: haptic_midi.py <event-node> <track-name> [--volume 0.0-1.0] [--repeat N]", 2)

    node = sys.argv[1]
    track_name = sys.argv[2].lower()

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

    if track_name not in TRACKS:
        fail(f"unknown track '{track_name}'. Available: {', '.join(TRACKS.keys())}", 2)

    volume = 1.0
    repeat = 1

    i = 3
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == "--volume" and i + 1 < len(sys.argv):
            try:
                volume = max(0.0, min(1.0, float(sys.argv[i + 1])))
            except ValueError:
                fail("volume must be a float between 0.0 and 1.0", 2)
            i += 2
        elif arg == "--repeat" and i + 1 < len(sys.argv):
            try:
                repeat = max(1, min(5, int(sys.argv[i + 1])))
            except ValueError:
                fail("repeat must be an integer between 1 and 5", 2)
            i += 2
        else:
            i += 1

    try:
        from evdev import ecodes, ff  # noqa: PLC0415
        from evdev import InputDevice  # noqa: PLC0415
    except ImportError:
        fail("python-evdev is not installed — run: sudo pacman -S --needed python-evdev", 3)

    try:
        dev = InputDevice(real_node)
    except (OSError, PermissionError) as exc:
        fail(f"cannot open {real_node} ({exc})", 1)

    if not hasattr(dev, "upload_effect") or ecodes.EV_FF not in dev.capabilities():
        fail(f"device {node} does not support force feedback motors", 0)

    # Signal handler for clean exit
    running_effect_id = None

    def cleanup(sig=None, frame=None):
        if running_effect_id is not None:
            try:
                dev.erase_effect(running_effect_id)
            except Exception:
                pass
        sys.exit(0)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    track = TRACKS[track_name]
    max_duration_sec = 15.0
    start_time = time.time()

    for r in range(repeat):
        if time.time() - start_time > max_duration_sec:
            break
        for freq, duration_ms, is_strong, gain in track:
            if time.time() - start_time > max_duration_sec:
                break
            if freq <= 0 or gain <= 0:
                time.sleep(duration_ms / 1000.0)
                continue

            mag = int(min(65535, max(0, 65535 * volume * gain)))
            if is_strong:
                strong_mag = mag
                weak_mag = int(mag * 0.45)
            else:
                strong_mag = int(mag * 0.35)
                weak_mag = mag

            rumble = ff.Rumble(strong_magnitude=strong_mag, weak_magnitude=weak_mag)
            effect = ff.Effect(
                ecodes.FF_RUMBLE,
                -1,
                0,
                ff.Trigger(0, 0),
                ff.Replay(duration_ms, 0),
                ff.EffectType(ff_rumble_effect=rumble),
            )

            try:
                running_effect_id = dev.upload_effect(effect)
                dev.write(ecodes.EV_FF, running_effect_id, 1)
            except OSError:
                pass

            time.sleep(duration_ms / 1000.0)

            if running_effect_id is not None:
                try:
                    dev.erase_effect(running_effect_id)
                except Exception:
                    pass
                running_effect_id = None

    cleanup()


if __name__ == "__main__":
    main()
