# omycontroller Pro Control Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `omycontroller`, an advanced Gamepad Control Center and Diagnostic Suite for Omarchy Linux with a 5-tab Segmented Pro Control Deck, Gamepadla-style stick circularity radar, hardware diagnostics sheet, simulator mode, and deploy to GitHub `@MISTERNEGATIVE21`.

**Architecture:** A long-running Quickshell service (`Service.qml`) that monitors `/sys` and evdev, generates virtual demo inputs when in simulator mode, tracks polling rate & latency jitter, and supplies live state to a bar pill (`BarWidget.qml`) and an anchored popout panel (`Panel.qml`) featuring 5 tabs (Overview, Sticks & Triggers, Haptics Studio, Motion & Gyro, Device Specs).

**Tech Stack:** Quickshell (QML / QtQuick 6 / JS), Bash, Python 3 (`evdev`), Linux sysfs / input subsystem, Git / GitHub CLI (`gh`).

**Spec:** [`docs/superpowers/specs/2026-09-18-omycontroller-pro-control-deck-design.md`](file:///home/mister/Documents/GitHub/omycontroller/docs/superpowers/specs/2026-09-18-omycontroller-pro-control-deck-design.md)

## Global Constraints
- Plugin ID: `omycontroller`
- Plugin Name: `omycontroller`
- Kinds: `["service", "bar-widget"]`
- `keepLoaded: true` in `manifest.json`
- Must pass `omarchy plugin validate .` without errors
- No sudo for installation or runtime
- Scripts executable (`755`), QML/JS/JSON/MD/SVG read-write non-executable (`644`)
- Theme-aware styling utilizing `qs.Commons` (`Color`, `Style`) and `qs.Ui`

---

### Task 1: Gamepadla SVG Vector Assets & Manifest Schema

**Files:**
- Create: `assets/icon_cable.svg`
- Create: `assets/icon_dongle.svg`
- Create: `assets/icon_bt.svg`
- Create: `assets/badge_hall.svg`
- Create: `assets/badge_tmr.svg`
- Create: `assets/badge_polling.svg`
- Modify: `manifest.json`
- Test: `tests/validate.test.sh`

**Interfaces:**
- Produces: Vector SVG icons in `assets/` and updated `manifest.json` with plugin id `omycontroller`.

- [ ] **Step 1: Write test for manifest validation**

Create `tests/validate.test.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
omarchy plugin validate .
echo "Manifest is valid!"
```
Make executable: `chmod +x tests/validate.test.sh`

- [ ] **Step 2: Run test to verify current state**

Run: `bash tests/validate.test.sh`
Expected: Output showing current plugin is valid.

- [ ] **Step 3: Create SVG vector assets**

Create `assets/icon_cable.svg`:
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 2v6"/>
  <rect x="7" y="8" width="10" height="7" rx="2"/>
  <path d="M9 15v5a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2v-5"/>
  <line x1="10" y1="2" x2="10" y2="4"/>
  <line x1="14" y1="2" x2="14" y2="4"/>
</svg>
```

Create `assets/icon_dongle.svg`:
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="8" y="2" width="8" height="6" rx="1"/>
  <rect x="6" y="8" width="12" height="12" rx="3"/>
  <circle cx="12" cy="14" r="2"/>
  <path d="M12 18v2"/>
</svg>
```

Create `assets/icon_bt.svg`:
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="6.5 6.5 17.5 17.5 12 23 12 1 17.5 6.5 6.5 17.5"/>
</svg>
```

Create `assets/badge_hall.svg`:
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none">
  <rect width="32" height="32" rx="6" fill="#3B82F6" fill-opacity="0.2"/>
  <circle cx="16" cy="16" r="9" stroke="#60A5FA" stroke-width="2"/>
  <circle cx="16" cy="16" r="4" fill="#3B82F6"/>
  <path d="M16 4v3M16 25v3M4 16h3M25 16h3" stroke="#93C5FD" stroke-width="2" stroke-linecap="round"/>
</svg>
```

Create `assets/badge_tmr.svg`:
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none">
  <rect width="32" height="32" rx="6" fill="#10B981" fill-opacity="0.2"/>
  <circle cx="16" cy="16" r="10" stroke="#34D399" stroke-width="2"/>
  <path d="M11 16l3.5 3.5L21 12" stroke="#10B981" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

Create `assets/badge_polling.svg`:
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none">
  <rect width="32" height="32" rx="6" fill="#8B5CF6" fill-opacity="0.2"/>
  <path d="M13 5L7 17h6l-2 10 12-14h-6l4-8z" fill="#A78BFA"/>
</svg>
```

- [ ] **Step 4: Update `manifest.json`**

Update `manifest.json` with ID `omycontroller`, name `omycontroller`, author `misternegative21`, version `2.0.0`, and full `barWidget.schema`.

- [ ] **Step 5: Run manifest test**

Run: `bash tests/validate.test.sh`
Expected: Exits 0 with "Manifest is valid!".

- [ ] **Step 6: Commit**

```bash
git add assets/ manifest.json tests/validate.test.sh
git commit -m "feat(manifest): update plugin id to omycontroller and add Gamepadla svg assets"
```

---

### Task 2: GamepadModel Engine & Unit Tests

**Files:**
- Modify: `GamepadModel.js`
- Create: `tests/model.test.js`

**Interfaces:**
- Consumes: Raw sysfs facts and axis/button snapshots
- Produces:
  - `classify(name, driver, vendor, product, axisCount, buttonCount)`
  - `circularityMetrics(x, y, history)`
  - `applyCurve(value, curveType, deadzone, outerDeadzone)`
  - `connectionIcon(busType, phys)`
  - `latencyMetrics(eventIntervals)`

- [ ] **Step 1: Write unit tests in `tests/model.test.js`**

Create `tests/model.test.js` to test:
- Xbox Series, DualSense, Switch Pro classification
- Circularity error computation
- Deadzone response curves (Linear, Dynamic, Smooth)
- Polling rate and jitter metrics
Run via `node tests/model.test.js`.

- [ ] **Step 2: Run test to verify it fails or exposes missing functions**

Run: `node tests/model.test.js`
Expected: FAIL due to missing functions `circularityMetrics`, `applyCurve`, etc.

- [ ] **Step 3: Implement new calculations in `GamepadModel.js`**

Add functions:
- `circularityMetrics(x, y, history)`: Computes radial magnitude $r$, tracks perimeter bounds, computes deviation from unit circle ($r=1$).
- `applyCurve(v, curve, dz, outer)`: Normalizes with inner and outer deadzones, applies curve functions:
  - `linear`: raw linear interpolation
  - `dynamic`: exponential cubic blend for precision center + fast outer
  - `smooth`: sinusoidal S-curve
- `connectionIcon(bus, phys)`: Returns asset path (`assets/icon_cable.svg`, `assets/icon_dongle.svg`, `assets/icon_bt.svg`)
- `formatHz(ms)`: Computes frequency from interval.

- [ ] **Step 4: Run test to verify it passes**

Run: `node tests/model.test.js`
Expected: PASS (All tests succeed).

- [ ] **Step 5: Commit**

```bash
git add GamepadModel.js tests/model.test.js
git commit -m "feat(model): add circularity metrics, response curves and connection resolver"
```

---

### Task 3: Background Service & Simulator Engine

**Files:**
- Modify: `Service.qml`
- Modify: `scripts/scan.sh`
- Create: `tests/scan.test.sh`

**Interfaces:**
- Produces:
  - Property `devices`: Map of active controllers
  - Property `simulatorActive`: Boolean toggle for virtual demo controller
  - Property `stats`: Live polling rate (Hz), min/avg/max latency
  - IPC handler: `toggleDemo`, `rescan`, `setRumble`, `calibrateGyro`

- [ ] **Step 1: Write test for `scripts/scan.sh`**

Create `tests/scan.test.sh` with mock sysfs structure and verify JSON fields (`id`, `input`, `event`, `name`, `driver`, `bus`, `vendor`, `product`, `motion`).
Run: `bash tests/scan.test.sh`.

- [ ] **Step 2: Run test to verify**

Run: `bash tests/scan.test.sh`
Expected: Verifies scan output matches JSON format.

- [ ] **Step 3: Implement Simulator Engine in `Service.qml`**

Add simulator timer & generator:
- In `Service.qml`, add property `bool demoMode: false`.
- Add `Timer` running at 60 Hz when `demoMode` is true (or when `devices` is empty and demo is requested).
- Generates a simulated P1 `Xbox Wireless Controller (Simulated)` with:
  - Orbiting left & right sticks (circular paths testing circularity radar)
  - Ramping LT/RT triggers
  - Cycling A/B/X/Y button presses
  - Sinusoidal gyro pitch/roll stream
  - Polling rate benchmark ~500 Hz
- Add IPC functions:
  - `toggleDemo()`
  - `calibrateGyro(slot)`
  - `setRumble(slot, weak, strong)`

- [ ] **Step 4: Run static check on QML and test scan script**

Run: `bash tests/scan.test.sh && omarchy plugin validate .`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Service.qml scripts/scan.sh tests/scan.test.sh
git commit -m "feat(service): add interactive simulator engine, latency tracker and IPC hooks"
```

---

### Task 4: Circularity Radar & Controller Art Components

**Files:**
- Create: `CircularityRadar.qml`
- Modify: `ControllerArt.qml`

**Interfaces:**
- Consumes: Raw stick $(X, Y)$, deadzone profile, player color
- Produces:
  - `CircularityRadar.qml`: Interactive Canvas radar with target circle, deadzone ring, coordinate tracer trail, and live circularity error percentage.
  - `ControllerArt.qml`: Updated silhouette rendering with button press glowing highlights and vector stick displacement.

- [ ] **Step 1: Create `CircularityRadar.qml`**

Build `CircularityRadar.qml`:
- Uses QtQuick `Canvas` (or 2D vector shapes)
- Draws Cartesian crosshairs, 50% guide circle, 100% boundary circle ($r = 1.0$), and deadzone shaded circle.
- Draws history trace trail points with fading alpha.
- Draws live coordinate marker dot and displays:
  - Live $X$ and $Y$ values
  - Distance $R = \sqrt{x^2 + y^2}$
  - Circularity Error percentage
  - Center Drift error percentage

- [ ] **Step 2: Update `ControllerArt.qml`**

- Add glowing drop-shadow / border highlights when buttons are pressed.
- Ensure Xbox, PlayStation DualSense (touchpad + lightbar), Switch Pro, and Joystick layouts react smoothly.
- Support `mini` mode for the slot selector and full mode for the Overview tab.

- [ ] **Step 3: Validate plugin structure**

Run: `omarchy plugin validate .`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add CircularityRadar.qml ControllerArt.qml
git commit -m "feat(ui): add Gamepadla circularity radar and glowing controller vector art"
```

---

### Task 5: Segmented Pro Control Deck Popout (Panel.qml)

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Consumes: State from `Service.qml` (`devices`, `demoMode`, `selectedPad`)
- Produces: 5-tab Pro Control Deck:
  1. Header with slot selector (P1..P4) and Demo toggle
  2. Tab 1: Overview (silhouette, status chips with Gamepadla SVGs)
  3. Tab 2: Sticks & Triggers (Dual `CircularityRadar` + Deadzone sliders + Curve presets)
  4. Tab 3: Haptics Studio (LF/HF rumble mixer, rhythm test patterns, DualSense trigger modes)
  5. Tab 4: Motion & Gyro (6-DOF Artificial Horizon + calibration)
  6. Tab 5: Device Specs (Full Gamepadla hardware spec table)

- [ ] **Step 1: Implement Segmented Tab Bar**

In `Panel.qml`:
- Replace monolithic scroll view with an animated tab selector:
  `["Overview", "Sticks & Triggers", "Haptics", "Motion", "Device Info"]`.
- Style active tab with Omarchy's `Color.accent` and subtle background highlight.

- [ ] **Step 2: Implement Tab 1 (Overview)**

- Render `ControllerArt` with live inputs.
- Quick status chips for Connection (with SVG icon), Battery, and Latency.

- [ ] **Step 3: Implement Tab 2 (Sticks & Triggers)**

- Side-by-side Left and Right `CircularityRadar.qml`.
- Inner and outer deadzone sliders with live feedback.
- Curve preset picker: `[Linear]`, `[Dynamic]`, `[Smooth]`, `[Aggressive]`.
- Trigger deadzone and analog level bars.

- [ ] **Step 4: Implement Tab 3 (Haptics Studio)**

- Dual motor rumble mixer:
  - Low Frequency motor slider (0–100%)
  - High Frequency motor slider (0–100%)
- Pattern test buttons: `[Pulse]`, `[Heartbeat]`, `[Ramp]`, `[Heavy Burst]`.
- DualSense Adaptive Trigger mode selector (Off, Rigid, Pulse, Bow, Machine Gun) with start/force sliders.

- [ ] **Step 5: Implement Tab 4 (Motion & Gyro)**

- 6-DOF Artificial Horizon tilt gauge (drawing pitch and roll horizon lines).
- Accelerometer ($g$) and Gyro angular velocity meters.
- `[Calibrate Zero Drift]` button connected to `svc.calibrateGyro()`.

- [ ] **Step 6: Implement Tab 5 (Device Specs - Gamepadla Hardware Sheet)**

- Full diagnostic table:
  - Device Name, Vendor & Product ID (`045e:0b12`)
  - Connection & Bus Type with SVG icon
  - Kernel Driver (`xpadneo`, `hid-playstation`, etc.)
  - Device nodes: Joydev, Evdev, Motion IMU, Sysfs
  - Button & Axis counts
  - Live Polling Rate (Hz) & Latency Jitter (Min, Avg, Max)
  - Battery capacity, status, and health assessment

- [ ] **Step 7: Run static check and validate**

Run: `omarchy plugin validate .`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Panel.qml
git commit -m "feat(panel): implement 5-tab Segmented Pro Control Deck with diagnostics"
```

---

### Task 6: Bar Widget & Installation Scripts

**Files:**
- Modify: `BarWidget.qml`
- Modify: `install.sh`
- Modify: `uninstall.sh`

**Interfaces:**
- Produces:
  - `BarWidget.qml`: Status bar pill displaying gamepad glyph, connection SVG/badge, battery %, and tooltip latency.
  - `install.sh`: Fully automated Omarchy plugin install + Hyprland keybind + `.desktop` launcher.
  - `uninstall.sh`: Clean teardown script.

- [ ] **Step 1: Update `BarWidget.qml`**

- Wire service lookup to `bar.shell.serviceFor("omycontroller")`.
- Read manifest settings (`showBatteryPercent`, `showLatency`, `lowBatteryThreshold`, `pillStyle`).
- Add mini connection glyph and battery badge.

- [ ] **Step 2: Update `install.sh`**

- Update `PLUGIN_ID="omycontroller"`.
- Set keybind: `bind = SUPER, G, exec, omarchy-shell shell toggle omycontroller '{}'`.
- Generate `~/.local/share/applications/omycontroller.desktop` with category `Game;Utility;Settings;`.
- Add automatic local linking into `~/.config/omarchy/plugins/omycontroller`.
- Execute `omarchy-shell shell rescanPlugins` and enable via `omarchy plugin enable omycontroller --section right`.

- [ ] **Step 3: Update `uninstall.sh`**

- Clean up keybind marker `# omycontroller:gamepad`.
- Remove `~/.local/share/applications/omycontroller.desktop`.
- Remove `~/.config/omarchy/plugins/omycontroller` symlink.
- Execute `omarchy-shell shell rescanPlugins`.

- [ ] **Step 4: Run validation test**

Run: `bash tests/validate.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BarWidget.qml install.sh uninstall.sh
git commit -m "feat(install): update BarWidget and automated Omarchy installer for omycontroller"
```

---

### Task 7: Comprehensive Documentation & GitHub Deployment

**Files:**
- Modify: `README.md`
- Normalize file permissions
- Deploy to GitHub: `@MISTERNEGATIVE21`

- [ ] **Step 1: Update `README.md`**

- Document `omycontroller` branding, Pro Control Deck features, Gamepadla circularity radar, hardware diagnostics, simulator mode, and Omarchy plugin install commands.
- Provide keybindings, IPC reference, and architecture guide.

- [ ] **Step 2: Normalize file permissions**

- Scripts (`install.sh`, `uninstall.sh`, `scripts/*.sh`, `scripts/*.py`, `tests/*.sh`): `755`
- Code / Data (`*.qml`, `*.js`, `*.json`, `*.md`, `assets/*.svg`): `644`

- [ ] **Step 3: Run complete verification suite**

Run:
```bash
node tests/model.test.js
bash tests/scan.test.sh
bash tests/validate.test.sh
```
Expected: All tests pass.

- [ ] **Step 4: Configure GitHub Remote & Deploy**

- Check if remote `origin` exists. Set URL to `https://github.com/misternegative21/omycontroller.git`.
- Check if GitHub repo exists. If not, create public repo:
  `gh repo create misternegative21/omycontroller --public --source=. --remote=origin --push`
- Verify repository on GitHub.

- [ ] **Step 5: Install and verify in local Omarchy Shell**

Run `bash install.sh` and test IPC toggle:
```bash
omarchy-shell shell toggle omycontroller '{}'
```

- [ ] **Step 6: Commit final adjustments**

```bash
git add README.md
git commit -m "docs: finalize omycontroller documentation and deployment guide"
```
