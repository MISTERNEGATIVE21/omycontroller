# 🎮 omycontroller

> **The Pro Control Deck & Gamepad Diagnostics Suite for Omarchy**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Omarchy / Quickshell](https://img.shields.io/badge/Platform-Omarchy%20%2F%20Quickshell-ff69b4.svg)](https://github.com/omarchy)
[![Version: 2.0.0](https://img.shields.io/badge/Version-2.0.0-green.svg)](manifest.json)

**omycontroller** is a pro-grade gamepad control center, diagnostics deck, and status bar widget designed natively for Omarchy Shell (Quickshell). It bridges the gap between desktop Linux gaming and professional hardware telemetry: offering Gamepadla-standard circularity radar tests, deep hardware and sysfs diagnostics, live sub-millisecond input latency measurement, DualSense adaptive triggers, 6-axis gyro/motion calibration, and an interactive simulation engine.

```
┌ omycontroller ──────────────────────────────────────── P1 · Xbox Series pad ─┐
│ [Overview] [Sticks & Triggers] [Haptics] [Motion] [Device Specs]              │
├───────────────────────────────────────────────────────────────────────────────┤
│  🎯 CIRCULARITY RADAR (Gamepadla Benchmark)                                   │
│     Avg Error: 4.8%  ·  Max: 8.2%  ·  Quality: EXCELLENT                      │
│     [● Polar 32-point contour polygon vs 1.00 unit circle]                   │
│                                                                               │
│  ⚡ INPUT LATENCY & POLLING                                                   │
│     Live: 1.4 ms  ·  Min: 1.1 ms  ·  Max: 2.2 ms  ·  Effective: 714 Hz       │
│                                                                               │
│  🎛️ RESPONSE CURVES & DEADZONES                                               │
│     Curve: [Smooth]  ·  Left Deadzone: 6%  ·  Right Deadzone: 5%              │
│                                                                               │
│  📳 HAPTICS & ADAPTIVE TRIGGERS                                               │
│     Dual-Motor: LF 70% / HF 50%  ·  DualSense L2/R2: [Rigid / 85% Force]     │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## 📑 Table of Contents

- [Features](#-features)
- [The 5-Tab Pro Control Deck](#-the-5-tab-pro-control-deck)
- [Gamepadla Circularity Radar](#-gamepadla-circularity-radar)
- [Status Bar Widget](#-status-bar-widget)
- [Interactive Simulator Mode](#-interactive-simulator-mode)
- [Installation](#-installation)
- [Keybindings & Desktop Entry](#-keybindings--desktop-entry)
- [IPC Command Reference](#-ipc-command-reference)
- [Settings & Schema](#-settings--schema)
- [Architecture](#-architecture)
- [Hardware & Driver Matrix](#-hardware--driver-matrix)
- [Optional Dependencies](#-optional-dependencies)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)

---

## ✨ Features

- **5-Tab Segmented Pro Deck**: Dedicated tab views for *Overview*, *Sticks & Triggers*, *Haptics*, *Motion*, and *Device Specs*.
- **Gamepadla Circularity Radar**: Live 32-ray polar radar displaying stick travel contours, average circularity error %, min/max deviation, and benchmark ratings (Flawless, Excellent, Good, Fair, Poor).
- **Sub-Millisecond Input Latency**: True rolling evdev interval monitoring with live, minimum, maximum latency in milliseconds and real effective polling frequency (Hz).
- **Hardware Diagnostics Sheet**: Instant sysfs inspection showing device nodes (`/dev/input/js*`, `/dev/input/event*`), vendor/product IDs, kernel drivers, bus types, button/axis caps, and rumble features.
- **Advanced Response Curves & Deadzones**: Real-time non-linear filtering (**Linear**, **Dynamic**, **Smooth**, **Aggressive**) and custom axial deadzones persisted per gamepad model.
- **Dual-Motor Rumble & DualSense Haptics**: Independent low-frequency (LF) and high-frequency (HF) sliders, real-time rhythm test runner, and direct hidraw adaptive trigger programming (Rigid, Pulse, Bow, Gallop).
- **6-Axis Gyro & IMU Telemetry**: Real-time 3D vector drift bubble and orientation gauge with one-click stationary drift calibration.
- **Multi-Pad Support (P1–P4)**: Automatic slot assignment, hotplug tracking, and dedicated player color accents following active Omarchy themes.
- **Built-in Simulator Engine**: Interactive virtual controller allowing full testing of UI, circularity benchmarks, gyro motion, and haptics without requiring physical hardware.
- **Native Omarchy & Quickshell Integration**: Single-process architecture, theme token inheritance, zero external dependencies required for core telemetry.

---

## 🗂️ The 5-Tab Pro Control Deck

The popout deck is segmented into five focused tabs:

### 1. Overview
- **Model-Accurate Silhouette**: Live vector artwork for Xbox Series/One, DualSense/DualShock 4, Nintendo Switch Pro/Joy-Cons, Arcade Sticks, and HOTAS flight controllers.
- **Live Button & Axis Illumination**: Real-time visual feedback as sticks, triggers, bumpers, face buttons, and D-pad are pressed.
- **Multi-Pad Slot Switcher**: Switch between Player 1 through Player 4 with persistent status and slot indicators.
- **Connection & Power Telemetry**: Hardware bus detection (Wired USB, Bluetooth, 2.4GHz Dongle) and battery health status.
- **Live Latency Chip**: Displays real-time polling latency and refresh rate.

### 2. Sticks & Triggers
- **Circularity Radar**: Polar coordinates mapped against ideal 1.0 unit circle.
- **Circularity Error Metrics**: Average error percentage and max error rating based on Gamepadla benchmark standards.
- **Stick Coordinates**: Real-time normalized readout `(X, Y, Magnitude)` for both Left and Right analog sticks.
- **Response Curve Selector**: Switch between Linear, Dynamic, Smooth, and Aggressive response curves.
- **Deadzone Sliders**: Per-stick radial deadzone configuration (0% to 50%) with live deadzone preview rings.
- **Trigger Calibration**: Live analog trigger travel bars and trigger deadzone sliders.

### 3. Haptics
- **Dual-Motor Mixer**: Independent Low-Frequency (LF heavy rumble) and High-Frequency (HF light rumble) sliders.
- **Rumble Test Bench**: Trigger Weak, Strong, or Dual-motor rumble pulses.
- **Haptic Rhythm Runner**: Multi-pulse cadence tester for haptic feedback validation.
- **DualSense Adaptive Triggers**: Configure hardware trigger effects on compatible DualSense controllers:
  - `Off`: Free linear travel
  - `Rigid`: Continuous mechanical resistance
  - `Pulse`: Vibrating force pulses during trigger squeeze
  - `Bow`: Simulated bowstring tension curve
  - `Gallop`: Rhythmic stepped resistance

### 4. Motion
- **6-Axis Gyro & Accelerometer**: Normalized kernel readings (`EVIOCGABS`) displayed in a live orientation bubble.
- **Drift Vector Readout**: Real-time angular velocity and tilt vectors.
- **Stationary Drift Calibration**: One-tap gyro bias zeroing that computes baseline offsets and stores them in your controller profile.

### 5. Device Specs (Hardware Diagnostics Sheet)
- **Linux Device Nodes**: Primary joystick node (`/dev/input/jsX`) and event node (`/dev/input/eventX`).
- **Sysfs Topology**: Full sysfs device path and kernel subsystem binding.
- **Hardware Identifiers**: USB / Bluetooth Vendor ID (`VID`) and Product ID (`PID`).
- **Bus & Protocol**: Hardware bus (USB, Bluetooth, Dongle) and active protocol (XInput, DualSense, hid-nintendo, evdev).
- **Physical Capabilities**: Exact axis count, button count, force-feedback motor support, and companion motion sensor nodes.

---

## 🎯 Gamepadla Circularity Radar

Circularity testing assesses the mechanical and firmware precision of analog thumbsticks.

- **The Problem**: Poorly tuned analog sticks often suffer from premature clipping (square outer bounds, 15%+ error) or irregular deadzones, resulting in jerky aiming or lost diagonal sensitivity.
- **The omycontroller Solution**: As you rotate the stick along its perimeter, omycontroller samples 32 radial segments, calculates deviation from the ideal circle `R = 1.0`, and renders the real polygon contour in real time.

| Average Error | Quality Rating | Behavior |
|:-------------:|:--------------:|:---------|
| **< 3.0%**    | ⭐ **Flawless**   | True circular calibration (e.g., Hall Effect sticks, high-end controllers) |
| **3.0% – 7.0%** | 🟢 **Excellent**  | Industry standard for modern competitive gamepads |
| **7.0% – 12.0%**| 🟡 **Good**       | Minor diagonal over-reach, typical factory calibration |
| **12.0% – 18.0%**| 🟠 **Fair**       | Notable clipping or corner elongation |
| **> 18.0%**   | 🔴 **Poor**       | Severe square gate clipping or cardinal axis clamping |

Click **Reset Radar** at any time to clear accumulated coordinate history and run a fresh test pass.

---

## 🍸 Status Bar Widget

The status bar widget (`BarWidget.qml`) integrates into the Omarchy panel:

- **Vector Silhouette Icon**: Renders the active controller's layout silhouette in the bar.
- **Connection Glyphs**: Gamepadla SVG icons for Wired USB, Bluetooth, and 2.4GHz Dongle.
- **Battery Pill**: Shows lowest battery percentage across connected pads; paints in `urgent` color when below threshold and `accent` when charging.
- **Configurable Styles**:
  - `badge`: Mini silhouette + connection icon + battery/status badge.
  - `compact`: Streamlined mini silhouette + inline percentage text.
  - `iconOnly`: Clean minimalist icon showing controller silhouette.
- **Multi-Pad Tooltip**: Rich popover detailing all connected controllers, slot assignments, battery levels, and live input latencies.

---

## 🧪 Interactive Simulator Mode

No controller at hand? omycontroller includes a full **interactive hardware simulator**:

- Simulates an Xbox Series controller connected over 2.4GHz Wireless Dongle.
- Simulates realistic 600 Hz polling with sub-2 ms synthetic latency jitter.
- Animates analog sticks through orbiting Gamepadla circularity tests.
- Simulates sinusoidal 6-axis gyro motion and live button presses.
- Fully accessible via the Overview tab header button or the IPC command line.

---

## 🚀 Installation

### Option 1: Official Omarchy Plugin CLI (Recommended)

```bash
omarchy plugin add https://github.com/misternegative21/omycontroller.git --enable --yes
```

### Option 2: Automated Local Installer

Run the included `install.sh` script from the repository:

```bash
git clone https://github.com/misternegative21/omycontroller.git
cd omycontroller
bash install.sh
```

`install.sh` automatically:
1. Symlinks the repository to `~/.config/omarchy/plugins/omycontroller`.
2. Adds the `SUPER+G` keybinding to `~/.config/hypr/bindings.conf`.
3. Installs the `omycontroller.desktop` launcher in `~/.local/share/applications/`.
4. Triggers `omarchy-shell shell rescanPlugins` and enables the bar widget.

*(To cleanly remove everything later, simply run `bash uninstall.sh`)*.

### Option 3: Manual Installation

```bash
# Clone to Omarchy plugins directory
git clone https://github.com/misternegative21/omycontroller.git ~/.config/omarchy/plugins/omycontroller

# Rescan plugins in Omarchy Shell
omarchy-shell shell rescanPlugins

# Enable the plugin in the status bar
omarchy plugin enable omycontroller --section right
```

---

## ⌨️ Keybindings & Desktop Entry

- **Hyprland Keybinding**: Press `SUPER + G` to toggle the deck popout window at any time.
  ```ini
  # ~/.config/hypr/bindings.conf
  bind = SUPER, G, exec, omarchy-shell shell toggle omycontroller '{}'
  ```
- **Application Launcher**: Search for `omycontroller` or `gamepad` in Fuzzel, Rofi, or your application menu.

---

## 📡 IPC Command Reference

Control omycontroller headlessly via `omarchy-shell`:

### Toggle Deck Popout
```bash
omarchy-shell shell toggle omycontroller '{}'
```

### Open Deck
```bash
omarchy-shell shell open omycontroller '{}'
```

### Close Deck
```bash
omarchy-shell shell close omycontroller '{}'
```

### Toggle Demo / Simulator Mode
```bash
omarchy-shell shell invoke omycontroller toggleDemo '{}'
```

### Rescan Gamepad Hardware
```bash
omarchy-shell shell invoke omycontroller rescan '{}'
```

### Trigger Rumble Test
Fire a timed rumble burst on a controller slot (P1–P4):
```bash
# Parameters: target (slot or id), weak motor (0.0 - 1.0), strong motor (0.0 - 1.0)
omarchy-shell shell invoke omycontroller setRumble '{"target": 1, "weakOrValue": 0.8, "strong": 0.4}'
```

### Store Rumble Power Preference
```bash
# Set rumble strength multiplier for P1 to 75%
omarchy-shell shell invoke omycontroller setRumble '{"target": 1, "weakOrValue": 0.75}'
```

### Calibrate Gyro Drift
Zero stationary gyroscope offsets on Player 1:
```bash
omarchy-shell shell invoke omycontroller calibrateGyro '{"target": 1}'
```

---

## ⚙️ Settings & Schema

Configure widget options in `~/.config/omarchy/shell.json` or via `omarchy bar set`:

```json
{
  "id": "omycontroller",
  "showBatteryPercent": true,
  "showLatency": true,
  "lowBatteryThreshold": 15,
  "pillStyle": "badge"
}
```

| Setting | Type | Default | Description |
|:--------|:----:|:-------:|:------------|
| `showBatteryPercent` | `boolean` | `true` | Display battery percentage number on bar pill |
| `showLatency` | `boolean` | `true` | Include live input latency in pill tooltip |
| `lowBatteryThreshold` | `integer` | `15` | Battery % threshold for urgent color warning (5–50) |
| `pillStyle` | `string` | `"badge"` | Bar layout: `"badge"`, `"compact"`, or `"iconOnly"` |

---

## 🏗️ Architecture

```
omycontroller/
├── manifest.json            # Plugin contract (kinds: service + bar-widget)
├── Service.qml              # Headless background singleton (sysfs scanning, streams, IPC)
├── BarWidget.qml            # Status bar pill, tooltip, connection icons & deck host
├── Panel.qml                # 5-Tab Segmented Pro Control Deck popout window
├── ControllerArt.qml        # Procedural vector controller rendering (5 layouts)
├── CircularityRadar.qml     # Gamepadla 32-sample polar circularity radar canvas
├── GamepadModel.js          # Pure classification, circularity math & curve functions
├── assets/                  # Official Gamepadla connection & spec SVGs
│   ├── icon_cable.svg       # Wired connection icon
│   ├── icon_bt.svg          # Bluetooth connection icon
│   ├── icon_dongle.svg      # 2.4GHz wireless dongle icon
│   ├── badge_polling.svg    # Polling rate badge
│   ├── badge_hall.svg       # Hall effect sensor badge
│   └── badge_tmr.svg        # TMR sensor badge
├── scripts/
│   ├── scan.sh              # sysfs device hierarchy crawler (outputs JSON lines)
│   ├── gyro.py              # EVIOCGABS kernel gyro/accel event reader (stdlib)
│   ├── rumble.py            # evdev FF_RUMBLE one-shot test runner
│   └── triggers.py          # DualSense adaptive trigger hidraw writer
├── tests/
│   ├── model.test.js        # Unit test suite for GamepadModel.js
│   ├── scan.test.sh         # Mock sysfs crawler test
│   └── validate.test.sh     # Plugin contract & JSON schema validation
├── install.sh               # Automated symlink, keybind, desktop installer
└── uninstall.sh             # Reverts install modifications cleanly
```

### Architectural Guarantees:
- **Zero Additional Processes**: Operates entirely within the long-running `omarchy-shell` Quickshell engine.
- **Theme Token Integrity**: All colors adapt dynamically to Omarchy system themes (`Color.accent`, `Color.popups.*`, `Color.urgent`, `Style.font.*`).
- **Graceful Degradation**: If helper tools are absent, hardware scanning and basic display continue uninterrupted.

---

## 🎮 Hardware & Driver Matrix

| Controller Family | Linux Kernel Driver | Connection Modes | Features Supported |
|:------------------|:--------------------|:-----------------|:-------------------|
| **Xbox Series X\|S / One** | `xpadneo` / `xpad` / `xone` | USB, Bluetooth, Wireless Dongle | Vector art, latency, deadzones, trigger travel, rumble |
| **Sony DualSense (PS5)** | `hid-playstation` | USB (Wired), Bluetooth | Adaptive triggers (USB), 6-axis gyro, rumble, latency |
| **Sony DualShock 4 (PS4)** | `hid-playstation` / `hid-sony` | USB, Bluetooth | 6-axis gyro, rumble, battery, latency |
| **Nintendo Switch Pro** | `hid-nintendo` | USB, Bluetooth | 6-axis gyro, rumble, battery, latency |
| **Nintendo Joy-Cons** | `hid-nintendo` | Bluetooth | Gyro, battery, single/pair layout |
| **Steam Deck / Controller**| `hid-steam` / evdev | Internal / USB / BT | Vector art, latency, deadzones |
| **Arcade & Flight Sticks** | `joydev` / `hid-generic` | USB | Dedicated single-stick layout, throttle & hat axes |

---

## 📦 Optional Dependencies

omycontroller runs out of the box with zero external packages. Two optional features activate when standard utilities are present:

```bash
sudo pacman -S --needed linuxconsole python-evdev
```

- **`linuxconsole` (`jstest`)**: Provides live button/stick coordinate streaming and sub-millisecond evdev latency monitoring.
- **`python-evdev`**: Provides haptic rumble dispatch.
- **User Permissions**: Ensure your user belongs to the `input` group for force feedback and hidraw access:
  ```bash
  sudo usermod -aG input $USER
  ```

---

## 🔧 Troubleshooting

- **Status bar displays "—"**: No joystick devices detected. Check `ls -l /dev/input/js*`. Ensure necessary kernel modules (e.g. `xpadneo`, `hid-playstation`) are loaded.
- **Circularity Radar is static / no button lights**: Install `linuxconsole` (`sudo pacman -S linuxconsole`) so `jstest` can stream live inputs.
- **Rumble yields permission error**: Check permissions on `/dev/input/event*`. Run `sudo usermod -aG input $USER` and log back in.
- **Adaptive triggers not engaging**: DualSense adaptive triggers require a wired USB connection (the Linux Bluetooth kernel driver blocks userspace effect reports).
- **No gyro section displayed**: Controller does not feature an IMU (e.g., standard Xbox pads) or companion motion node was not paired.

---

## 📄 License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for full details.
