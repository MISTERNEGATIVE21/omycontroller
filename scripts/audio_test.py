#!/usr/bin/env python3
"""Quatro — scripts/audio_test.py

Controller 3.5mm Headphone Jack and Speaker Diagnostic Bench for Linux.
Probes PipeWire / ALSA audio sinks, detects onboard controller DACs
(DualSense, Xbox Wireless with DAC, USB gaming headsets), routes test tones
to controller hardware or system headphone output, and generates pure
sinusoidal test tones for Left, Right, and Stereo balance checks.

Usage:
  audio_test.py probe
  audio_test.py play <left|right|stereo> [sink-name]

Exit codes:
  0 - Success
  1 - General playback / system error
  2 - Argument / usage error
"""

import json
import math
import re
import shutil
import struct
import subprocess
import sys


def fail(msg: str, code: int = 1) -> None:
    sys.stderr.write("audio_test: " + msg + "\n")
    sys.exit(code)


def probe_sinks() -> dict:
    """Probe PipeWire / PulseAudio sinks and look for controller audio hardware."""
    sinks = []
    has_controller = False
    controller_sink = None
    active_sink = ""
    active_label = ""

    # Try pactl first as it provides clean structured device lists on PipeWire
    pactl = shutil.which("pactl")
    if pactl:
        try:
            out = subprocess.check_output(
                [pactl, "list", "sinks", "short"],
                universal_newlines=True,
                stderr=subprocess.DEVNULL,
                timeout=2.0,
            )
            for line in out.strip().splitlines():
                parts = line.split("\t")
                if len(parts) >= 2:
                    sid = parts[0]
                    name = parts[1]
                    fmt = parts[3] if len(parts) > 3 else ""
                    state = parts[4] if len(parts) > 4 else ""

                    # Check for controller signatures
                    is_ctrl = bool(
                        re.search(
                            r"dualsense|wireless_controller|playstation|sony_interactive|xbox|gamepad",
                            name,
                            re.I,
                        )
                    )
                    label = name
                    if "Headphones" in name:
                        label = "Headphones (3.5mm Jack)"
                    elif "Speaker" in name:
                        label = "Internal Speaker"
                    elif "HDMI" in name:
                        label = "HDMI Audio"
                    elif is_ctrl:
                        label = "Controller Integrated Audio (DAC)"

                    sink_obj = {
                        "id": sid,
                        "name": name,
                        "format": fmt,
                        "state": state,
                        "isController": is_ctrl,
                        "label": label,
                    }
                    sinks.append(sink_obj)

                    if is_ctrl and not controller_sink:
                        has_controller = True
                        controller_sink = sink_obj

                    if state == "RUNNING" and not active_sink:
                        active_sink = name
                        active_label = label
        except Exception:
            pass

    # If no RUNNING sink was picked, pick the first Headphones or first sink
    if not active_sink and sinks:
        for s in sinks:
            if "Headphones" in s["name"] or s["isController"]:
                active_sink = s["name"]
                active_label = s["label"]
                break
        if not active_sink:
            active_sink = sinks[0]["name"]
            active_label = sinks[0]["label"]

    return {
        "sinks": sinks,
        "hasControllerSink": has_controller,
        "controllerSink": controller_sink,
        "activeSink": active_sink,
        "activeLabel": active_label or (active_sink if active_sink else "Default System Output"),
    }


def generate_tone_pcm(channel: str, sample_rate: int = 48000) -> bytes:
    """Generate 16-bit signed little-endian stereo PCM byte stream."""
    buffer = bytearray()
    max_amp = int(32767 * 0.70)  # Safe 70% peak amplitude

    if channel == "left":
        # 440 Hz Left, silent Right for 450 ms
        duration = 0.45
        freq = 440.0
        num_samples = int(sample_rate * duration)
        for i in range(num_samples):
            t = i / sample_rate
            # 10ms smooth ramp up/down to prevent clicks
            env = 1.0
            if i < sample_rate * 0.01:
                env = i / (sample_rate * 0.01)
            elif i > num_samples - sample_rate * 0.01:
                env = (num_samples - i) / (sample_rate * 0.01)

            val_l = int(max_amp * env * math.sin(2 * math.pi * freq * t))
            val_r = 0
            buffer.extend(struct.pack("<hh", val_l, val_r))

    elif channel == "right":
        # 0 Left, 880 Hz Right for 450 ms
        duration = 0.45
        freq = 880.0
        num_samples = int(sample_rate * duration)
        for i in range(num_samples):
            t = i / sample_rate
            env = 1.0
            if i < sample_rate * 0.01:
                env = i / (sample_rate * 0.01)
            elif i > num_samples - sample_rate * 0.01:
                env = (num_samples - i) / (sample_rate * 0.01)

            val_l = 0
            val_r = int(max_amp * env * math.sin(2 * math.pi * freq * t))
            buffer.extend(struct.pack("<hh", val_l, val_r))

    elif channel == "stereo":
        # Alternating ping: 0.18s Left (523Hz) -> 0.05s gap -> 0.18s Right (659Hz) -> 0.05s gap -> 0.3s Both (784Hz)
        segments = [
            (523.25, 0.18, True, False),
            (0, 0.04, False, False),
            (659.25, 0.18, False, True),
            (0, 0.04, False, False),
            (783.99, 0.30, True, True),
        ]
        for freq, dur, play_l, play_r in segments:
            num_samples = int(sample_rate * dur)
            if freq == 0:
                buffer.extend(b"\x00\x00\x00\x00" * num_samples)
                continue
            for i in range(num_samples):
                t = i / sample_rate
                env = 1.0
                if i < sample_rate * 0.008:
                    env = i / (sample_rate * 0.008)
                elif i > num_samples - sample_rate * 0.008:
                    env = (num_samples - i) / (sample_rate * 0.008)

                wave_val = int(max_amp * env * math.sin(2 * math.pi * freq * t))
                val_l = wave_val if play_l else 0
                val_r = wave_val if play_r else 0
                buffer.extend(struct.pack("<hh", val_l, val_r))
    else:
        fail(f"invalid channel '{channel}'. Expected left, right, or stereo", 2)

    return bytes(buffer)


def play_tone(channel: str, sink: str = "") -> None:
    pcm_data = generate_tone_pcm(channel)

    # Prefer pw-cat, then paplay, then aplay
    pw_cat = shutil.which("pw-cat")
    paplay = shutil.which("paplay")
    aplay = shutil.which("aplay")

    cmd = None
    if pw_cat:
        cmd = [pw_cat, "-p", "--rate=48000", "--channels=2", "--format=s16"]
        if sink:
            cmd.extend(["--target", sink])
    elif paplay:
        cmd = [paplay, "--raw", "--rate=48000", "--channels=2", "--format=s16le"]
        if sink:
            cmd.extend(["--device", sink])
    elif aplay:
        cmd = [aplay, "-q", "-r", "48000", "-f", "S16_LE", "-c", "2"]
        if sink:
            cmd.extend(["-D", sink])

    if not cmd:
        fail("no audio playback utility found (need pw-cat, paplay, or aplay)", 1)

    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        proc.communicate(input=pcm_data, timeout=3.0)
    except Exception as exc:
        fail(f"playback failed: {exc}", 1)


def main() -> None:
    if len(sys.argv) < 2:
        fail("usage: audio_test.py <probe|play> [channel] [sink-name]", 2)

    action = sys.argv[1].lower()
    if action == "probe":
        result = probe_sinks()
        print(json.dumps(result, indent=2))
        sys.exit(0)
    elif action == "play":
        if len(sys.argv) < 3:
            fail("usage: audio_test.py play <left|right|stereo> [sink-name]", 2)
        channel = sys.argv[2].lower()
        if channel not in ("left", "right", "stereo"):
            fail("invalid channel: must be left, right, or stereo", 2)
        sink = sys.argv[3] if len(sys.argv) > 3 else ""
        play_tone(channel, sink)
        sys.exit(0)
    else:
        fail(f"unknown command '{action}'", 2)


if __name__ == "__main__":
    main()
