# Design Specification: omycontroller (Pro Control Deck & Diagnostics)

**Date**: 2026-09-18  
**Author**: misternegative21 & Antigravity  
**Plugin ID**: `omycontroller`  
**Repository**: `misternegative21/omycontroller`  
**Target Environment**: Omarchy Linux / Hyprland / Quickshell (`omarchy-shell`)

---

## 1. Executive Summary

`omycontroller` is an advanced gamepad control center, input visualizer, and diagnostic suite built for the Omarchy Linux desktop. Designed according to the official Omarchy plugin specification, it integrates seamlessly into `omarchy-shell` as both a long-running background service and a status bar widget with an expandable, segmented "Pro Control Deck" popout panel.

It provides real-time latency and polling rate benchmarking inspired by Gamepadla, a Gamepadla-style stick circularity radar, multi-layout vector controller silhouettes, dual-motor rumble mixing, DualSense adaptive trigger tuning, 6-DOF gyro motion sensing with drift calibration, comprehensive hardware specifications, and an interactive virtual simulator bench.

---

## 2. Plugin Architecture & Identity

### 2.1 Manifest (`manifest.json`)
The manifest conforms to Omarchy Shell `schemaVersion: 1`:
```json
{
  "schemaVersion": 1,
  "id": "omycontroller",
  "name": "omycontroller",
  "version": "2.0.0",
  "author": "misternegative21",
  "description": "Pro gamepad control center & diagnostics: Gamepadla circularity radar, latency benchmark, battery, deadzones, rumble, and DualSense haptics.",
  "kinds": [
    "service",
    "bar-widget"
  ],
  "keepLoaded": true,
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "omycontroller",
    "description": "Gamepad status pill and pro control center",
    "category": "Gaming",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {
      "showBatteryPercent": true,
      "showLatency": true,
      "lowBatteryThreshold": 15,
      "pillStyle": "badge"
    },
    "schema": [
      {
        "key": "showBatteryPercent",
        "type": "boolean",
        "label": "Show lowest battery percentage on bar",
        "defaultValue": true
      },
      {
        "key": "showLatency",
        "type": "boolean",
        "label": "Display live input latency in tooltip",
        "defaultValue": true
      },
      {
        "key": "lowBatteryThreshold",
        "type": "integer",
        "label": "Low battery alert threshold (%)",
        "defaultValue": 15,
        "min": 5,
        "max": 50,
        "step": 5
      },
      {
        "key": "pillStyle",
        "type": "string",
        "label": "Bar Pill Style (badge / compact / iconOnly)",
        "defaultValue": "badge"
      }
    ]
  }
}
```

### 2.2 Host Injection & Lifecycle
- `omarchy-shell` mounts `Service.qml` as a singleton when enabled via `PluginRegistry`.
- `BarWidget.qml` obtains the service instance using `bar.shell.serviceFor("omycontroller")`.
- `Panel.qml` is dynamically loaded by `BarWidget.qml` via a QML `Loader` with anchor and bar properties injected.
- Hot-reload is supported across updates without restarting the shell.

---

## 3. User Interface: Segmented Pro Control Deck

The UI popout conforms to the Omarchy design system (`qs.Commons`, `qs.Ui`, `Color`, `Style`) and adopts a 5-tab segmented layout with animated cards and subtle borders.

### 3.1 Header & Slot Bar
- **Header**: Displays `OMYCONTROLLER`, slot count badge, and a **Simulator Mode** toggle button (`⚡ Demo`).
- **Device Slot Selector**: 4 interactive slot pills (`P1`, `P2`, `P3`, `P4`) color-coded by player index (`P1`: Blue/Cyan, `P2`: Red/Crimson, `P3`: Green/Emerald, `P4`: Yellow/Amber). Shows controller silhouette and battery % if connected.

### 3.2 Navigation Tabs
1. **Overview**:
   - Model-accurate vector controller silhouette (Xbox Series/One, PS5 DualSense/DS4, Switch Pro, Flight/Arcade Stick, Generic).
   - Real-time button glow on input press.
   - Vector stick displacement dots and analog trigger fill bars.
   - Quick status cards: Connection badge with Gamepadla SVG (Cable, BT, Dongle), battery indicator, and latency pill.
2. **Sticks & Triggers**:
   - **Gamepadla Circularity Radar**: Dual circular radars showing live $(X, Y)$ coordinate tracking, target circular boundary ($r = 1.0$), inner deadzone ring, and motion tracer trail.
   - **Error Calculations**: Real-time stick circularity error % and resting center drift error %.
   - **Tuning Controls**: Inner deadzone slider, outer deadzone boundary slider, anti-deadzone offset, and response curve presets (Linear, Dynamic, Aggressive, Smooth).
   - **Trigger Calibration**: Analog trigger stroke indicators with customizable activation deadzones.
3. **Haptics & Vibration Studio**:
   - **Dual-Motor Mixer**: Independent Low-Frequency (heavy weight) and High-Frequency (light weight) amplitude sliders.
   - **Vibration Rhythms**: Preset test patterns (Single Pulse, Double Pulse, Heartbeat, Ramp Up, Heavy Burst).
   - **DualSense Adaptive Trigger Studio**: Mode selector (Off, Rigid, Pulse, Bow, Machine Gun) with start/stop trigger resistance tuning.
4. **Motion & Gyro**:
   - 6-DOF Artificial Horizon / 3D Tilt Bubble: Live pitch, roll, and yaw representation.
   - Accelerometer ($g$) and Gyroscope ($^\circ/\text{s}$) velocity bars.
   - 1-Click Zero-Drift Calibration: Captures resting sensor bias and persists to device profile.
5. **Device Specs & Diagnostics (Gamepadla Sheet)**:
   - Comprehensive hardware specification sheet:
     - **Device Name & Manufacturer**: e.g., Microsoft Xbox Wireless Controller (`045e:0b12`)
     - **Connection & Bus Type**: Bus 0005 (Bluetooth) / Bus 0003 (USB) with Gamepadla SVG icon
     - **Kernel Driver**: e.g. `xpadneo`, `hid-playstation`, `hid-nintendo`, `xpad`
     - **Device Paths**: Joydev (`/dev/input/js0`), Evdev (`/dev/input/event22`), Motion node (`/dev/input/event23`), Sysfs path
     - **Hardware Layout**: Detected axis count, button count, hat switch count
     - **Polling Rate & Latency Benchmark**: Live Hz, Min latency, Avg latency, Max jitter
     - **Power & Battery**: Kernel `power_supply` node, charging status, health rating

### 3.3 Simulator / Demo Bench
When enabled (or when no physical controller is plugged in):
- Simulates realistic input streams directly in `Service.qml`:
  - Stick coordinates sweeping orbital paths to exercise circularity radar.
  - Analog triggers smoothly oscillating.
  - Face buttons and bumpers cycling.
  - Gyro pitch/roll oscillating.
- Allows complete verification of UI, vector art, radar, and animations on any workstation.

---

## 4. Vector SVG Assets & Gamepadla Iconography

Assets stored in `assets/`:
- `icon_cable.svg`: Wired USB connection icon.
- `icon_dongle.svg`: 2.4 GHz wireless adapter icon.
- `icon_bt.svg`: Bluetooth wireless icon.
- `badge_hall.svg`: Hall Effect magnetic sensor badge.
- `badge_tmr.svg`: TMR sensor badge.
- `badge_polling.svg`: High polling rate / benchmark badge.

---

## 5. Diagnostics & Hardware Engine

### 5.1 Latency & Polling Rate Engine
- Samples high-precision evdev input event timestamps.
- Computes:
  $$\Delta t = t_i - t_{i-1}$$
  $$\text{Instantaneous Polling Rate (Hz)} = \frac{1}{\Delta t}$$
  $$\text{Rolling Latency (ms)} = \text{Average}(\Delta t) \times 1000$$
- Tracks min latency, max latency, and jitter variance.

### 5.2 Stick Circularity & Deadzone Math
- Raw coordinates $(x, y) \in [-1, 1]$.
- Magnitude $r = \sqrt{x^2 + y^2}$.
- Deadzone application:
  $$r_{\text{eff}} = \max\left(0, \frac{r - \text{inner}}{\text{outer} - \text{inner}}\right)$$
- Circularity error: deviation of maximum reached perimeter points from expected $r = 1.0$.

### 5.3 Backend Helper Scripts
- `scripts/scan.sh`: Enumerates `/sys/class/input/js*`, pairs companion motion sensor nodes, checks `power_supply`, outputs single-line JSON stream.
- `scripts/rumble.py`: Low-level evdev force feedback interface supporting dual-motor envelope modulation.
- `scripts/triggers.py`: DualSense USB/BT hidraw packet generator for adaptive trigger effects.
- `scripts/gyro.py`: Standard library evdev reader streaming normalized gyro/accelerometer data.

---

## 6. Official Omarchy Integration & Installation

### 6.1 Installation Script (`install.sh`)
1. Installs/symlinks repo to `~/.config/omarchy/plugins/omycontroller`.
2. Adds `SUPER+G` keybind toggle to `~/.config/hypr/bindings.conf` (with `# omycontroller:gamepad` marker).
3. Installs desktop entry `~/.local/share/applications/omycontroller.desktop` for Fuzzel / application menu.
4. Notifies `omarchy-shell` to rescan plugins:
   `omarchy-shell shell rescanPlugins`
5. Enables plugin on status bar:
   `omarchy plugin enable omycontroller --section right`

### 6.2 Uninstallation Script (`uninstall.sh`)
- Disables plugin via `omarchy plugin disable omycontroller`.
- Cleans up keybind marker from Hyprland config.
- Removes desktop application entry.

---

## 7. Verification & Testing Strategy

- **Static Validation**: `omarchy plugin validate .` passes with zero errors.
- **Unit Testing**:
  - `tests/model.test.js`: Validates vendor ID parsing, driver detection, button layouts, deadzone math, and circularity error calculations.
  - `tests/scan.test.sh`: Runs `scan.sh` against mock sysfs hierarchy to verify JSON output.
- **Simulator Smoke Test**: Confirms demo mode drives all 5 tabs and UI components smoothly.

---

## 8. Deployment to GitHub (`@MISTERNEGATIVE21`)

- Normalize file permissions (`644` for QML, JS, SVG, JSON, Markdown; `755` for scripts).
- Initialize git repository and set remote to `https://github.com/misternegative21/omycontroller.git`.
- Create and push to public repository on GitHub via `gh repo create`.
