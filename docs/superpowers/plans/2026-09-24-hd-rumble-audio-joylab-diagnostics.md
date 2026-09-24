# HD Rumble MIDI, Audio Diagnostics, Mario JoyLab Game & Multi-Sector Scorecard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an advanced HD Rumble MIDI song player, 3.5mm/speaker audio diagnostic bench, a 60 FPS playable "Mario JoyLab" joystick benchmark game, and a 6-sector hardware performance scorecard with Gamepadla model comparison and markdown report export.

**Architecture:** A modular suite adding dedicated Python test runners (`scripts/haptic_midi.py`, `scripts/audio_test.py`), pure analytical scoring in `GamepadModel.js`, a standalone 60 FPS platformer component (`JoyLabGame.qml`), and expanded 6-tab deck navigation in `Panel.qml` with `Service.qml` IPC support.

**Tech Stack:** Qt/QML (Quickshell, QtQuick), JavaScript (ES6), Python 3 (`evdev`, `struct`, `wave`, PipeWire/ALSA), Bash.

**Spec:** [`docs/superpowers/specs/2026-09-24-hd-rumble-audio-joylab-diagnostics-design.md`](file:///home/mister/Documents/GitHub/omycontroller/docs/superpowers/specs/2026-09-24-hd-rumble-audio-joylab-diagnostics-design.md)

## Global Constraints
- All QML files must adhere to existing `Color`, `Style`, `PanelSectionHeader`, and `Button` conventions.
- All Python scripts must strictly validate device paths (`/dev/input/event*`), reject traversal, enforce integer/range bounds, and run without root.
- All unit tests (`tests/model.test.js`) and security tests (`tests/security.test.sh`) must pass 100%.
- File permissions must remain compliant (644 for QML/JS/MD, 755 for executable Python/Bash scripts).

---

### Task 1: HD Rumble MIDI Script (`scripts/haptic_midi.py`) & Security Tests

**Files:**
- Create: `scripts/haptic_midi.py`
- Modify: `tests/security.test.sh`

**Interfaces:**
- CLI: `python3 scripts/haptic_midi.py <event-node> <track-name> [--volume 0.0-1.0] [--repeat N]`
- Exit codes: 0 (success), 1 (general error), 2 (security / argument failure), 3 (python-evdev missing).

- [ ] **Step 1: Write the failing security test in `tests/security.test.sh`**

```bash
# Add to tests/security.test.sh:
printf '\n%s\n' '--- Testing scripts/haptic_midi.py ---'
assert_fail "haptic_midi.py: rejects missing arguments" python3 scripts/haptic_midi.py
assert_fail "haptic_midi.py: rejects path traversal" python3 scripts/haptic_midi.py "../../etc/shadow" mario
assert_fail "haptic_midi.py: rejects regular file" python3 scripts/haptic_midi.py "/etc/hosts" mario
assert_fail "haptic_midi.py: rejects malformed node name" python3 scripts/haptic_midi.py "/dev/input/js0" mario
assert_fail "haptic_midi.py: rejects unknown track" python3 scripts/haptic_midi.py "/dev/input/event0" nonexistent_track
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/security.test.sh`  
Expected: FAIL with "scripts/haptic_midi.py: No such file or directory".

- [ ] **Step 3: Implement `scripts/haptic_midi.py`**

Implement `scripts/haptic_midi.py` with:
- Strict path validation: `re.match(r"^/dev/input/event\d+$", node)`, canonicalization, `stat.S_ISCHR`.
- Track library with note frequencies and durations:
  - `mario`: Intro + Main Theme (E7, E7, E7, C7, E7, G7, G6, C7, G6, E6, A6, B6, Bb6, A6, G6, E7, G7, A7, F7, G7, E7, C7, D7, B6).
  - `zelda`: Overworld Theme (Bb4, F4, Bb4, C5, D5, Eb5, F5, F5, F5, F#5, G#5, Bb5, Bb5, Bb5, Ab5, F#5, Ab5, F#5, F5).
  - `tetris`: Type A / Korobeiniki (E5, B4, C5, D5, C5, B4, A4, A4, C5, E5, D5, C5, B4, C5, D5, E5, C5, A4, A4).
  - `pokemon`: Red/Blue Battle Intro (G4, F#4, G4, F#4, G4, G4, F#4, F#4, G4, A4, B4, C5, D5).
  - `coin`: Quick chime (B5, 100ms -> E6, 350ms).
  - `oneup`: 1-Up fanfare (E6, G6, E7, C7, D7, G7).
- Frequency-to-pulse modulation: Pre-upload `ff.Rumble` effects to `dev.upload_effect()` and trigger `dev.write(ecodes.EV_FF, effect_id, 1)` with `time.sleep()`.
- Maximum play duration ceiling of 15 seconds.
- Chmod 755.

- [ ] **Step 4: Run security test to verify it passes**

Run: `bash tests/security.test.sh`  
Expected: PASS for `scripts/haptic_midi.py` checks.

- [ ] **Step 5: Commit**

```bash
git add scripts/haptic_midi.py tests/security.test.sh
git commit -m "feat(haptics): add haptic_midi.py melody player with Nintendo and retro track library"
```

---

### Task 2: Speaker & Audio Jack Diagnostic Script (`scripts/audio_test.py`) & Security Tests

**Files:**
- Create: `scripts/audio_test.py`
- Modify: `tests/security.test.sh`

**Interfaces:**
- CLI:
  - `python3 scripts/audio_test.py probe` -> Prints JSON `{"sinks": [...], "hasControllerSink": bool, "activeSink": "..."}`
  - `python3 scripts/audio_test.py play <left|right|stereo> [sink-name]` -> Plays 16-bit PCM sinusoidal tone via `pw-cat`, `paplay`, or `aplay`.
- Exit codes: 0 (success), 1 (general error), 2 (argument error).

- [ ] **Step 1: Write the failing security test in `tests/security.test.sh`**

```bash
# Add to tests/security.test.sh:
printf '\n%s\n' '--- Testing scripts/audio_test.py ---'
assert_fail "audio_test.py: rejects missing arguments" python3 scripts/audio_test.py
assert_fail "audio_test.py: rejects unknown command" python3 scripts/audio_test.py invalid_cmd
assert_fail "audio_test.py: rejects invalid channel" python3 scripts/audio_test.py play center
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/security.test.sh`  
Expected: FAIL with "scripts/audio_test.py: No such file or directory".

- [ ] **Step 3: Implement `scripts/audio_test.py`**

Implement `scripts/audio_test.py` with:
- `probe()`: Uses `pactl list sinks short` or `wpctl status` to inspect audio sinks. Matches controller keywords (`dualsense`, `wireless controller`, `xbox`, `headset`, `usb audio`). Returns JSON summary.
- `play(channel, sink_name)`:
  - Generates 16-bit stereo PCM byte buffer using `math.sin` and `struct.pack`.
  - Left: 440 Hz Left, 0 Right (0.4s).
  - Right: 0 Left, 880 Hz Right (0.4s).
  - Stereo: Two-tone ping (440 Hz L -> 660 Hz R -> 880 Hz Stereo, 0.6s).
  - Pipes raw PCM to `pw-cat -p --rate=48000 --channels=2 --format=s16le` or `paplay --raw --rate=48000 --channels=2 --format=s16le` or `aplay -r 48000 -f S16_LE -c 2`.
- Chmod 755.

- [ ] **Step 4: Run security test and verify probe output**

Run: `bash tests/security.test.sh && python3 scripts/audio_test.py probe`  
Expected: PASS, and valid JSON returned.

- [ ] **Step 5: Commit**

```bash
git add scripts/audio_test.py tests/security.test.sh
git commit -m "feat(audio): add audio_test.py for controller jack probe and stereo tone generation"
```

---

### Task 3: Scorecard & Benchmark Engine in `GamepadModel.js` & Unit Tests

**Files:**
- Modify: `GamepadModel.js`
- Modify: `tests/model.test.js`

**Interfaces:**
- Produces in `GamepadModel.js`:
  - `computePerformanceScorecard(device, stats, joyLabStats)` -> Returns `{ overallGrade: "S"|"A+"|"A"|"B"|"C"|"D", overallScore: 92, sectors: { sticks: {...}, latency: {...}, buttons: {...}, haptics: {...}, motion: {...}, connectivity: {...} }, gamepadlaMatch: {...} }`
  - `exportMarkdownReport(device, scorecard)` -> Returns formatted markdown text string ready for clipboard.

- [ ] **Step 1: Write unit tests in `tests/model.test.js`**

Add tests for:
- Sector grading thresholds (Sticks, Latency, Buttons, Haptics, Motion, Connectivity).
- Missing/partial data handling (gracefully handles null gyro or idle polling rate).
- Markdown export structure and Gamepadla reference match comparison.

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/model.test.js`  
Expected: FAIL ("computePerformanceScorecard is not a function").

- [ ] **Step 3: Implement functions in `GamepadModel.js`**

Implement:
- `computePerformanceScorecard(dev, stats, joyLabStats)`:
  - Sector 1: Sticks. Calculates score from `dev.circularity.left.error` and `dev.circularity.right.error` (or `joyLabStats.stickError`), center drift, snapback count.
  - Sector 2: Polling & Latency. Evaluates `stats.hz` (or `dev.hz`), average ms latency, and jitter.
  - Sector 3: Buttons & Triggers. Evaluates active buttons, actuation response, trigger axis travel.
  - Sector 4: Haptics. Checks rumble capability (`hasRumble`, `dev.event`), HD rumble support, profile power.
  - Sector 5: IMU Motion. Checks companion motion event, gyro bias stability, gyro sampling.
  - Sector 6: Connectivity & Audio. Checks bus type (`usb`, `bluetooth`, `dongle`), battery status, audio sink readiness.
  - Overall Grade computation (weighted average of sectors: 0-100 mapped to S / A+ / A / B / C / D).
  - Side-by-side comparison against `GamepadlaCatalog.find(dev.modelLabel || dev.name, dev.maker)`.
- `exportMarkdownReport(dev, card)`: Formats clean Markdown text containing controller name, VID/PID, overall grade, sector grades, Gamepadla comparison, and date.

- [ ] **Step 4: Run unit tests to verify they pass**

Run: `node --test tests/model.test.js`  
Expected: All 16+ unit tests PASS.

- [ ] **Step 5: Commit**

```bash
git add GamepadModel.js tests/model.test.js
git commit -m "feat(diagnostics): add multi-sector performance scorecard engine and markdown exporter"
```

---

### Task 4: Service Integration in `Service.qml`

**Files:**
- Modify: `Service.qml`

**Interfaces:**
- Consumes: `scripts/haptic_midi.py`, `scripts/audio_test.py`.
- Produces in `Service.qml`:
  - `property string hapticMidiScript`
  - `property string audioTestScript`
  - `property var audioProbeState`
  - `function playMelody(id, trackName, volume): bool`
  - `function stopMelody(): bool`
  - `function probeAudio(): void`
  - `function playAudioTone(channel, sinkName): bool`
  - IPC handler methods for `playMelody`, `stopMelody`, `playAudioTone`, `probeAudio`.

- [ ] **Step 1: Add script paths and properties in `Service.qml`**

Add:
- `readonly property string hapticMidiScript: Qt.resolvedUrl("scripts/haptic_midi.py").toString().replace(/^file:\/\//, "")`
- `readonly property string audioTestScript: Qt.resolvedUrl("scripts/audio_test.py").toString().replace(/^file:\/\//, "")`
- `property var audioInfo: ({ sinks: [], hasControllerSink: false, activeSink: "" })`

- [ ] **Step 2: Implement audio probing and tone playback in `Service.qml`**

Implement:
- `function probeAudio()`: Dispatches `python3 scripts/audio_test.py probe` and updates `audioInfo`.
- `function playAudioTone(channel, sink)`: Dispatches `python3 scripts/audio_test.py play <channel> [sink]`.

- [ ] **Step 3: Implement melody playback and stop in `Service.qml`**

Implement:
- `function playMelody(id, trackName, volume)`: Checks device event node; runs `python3 scripts/haptic_midi.py /dev/input/<event> <track> --volume <vol>`.
- `function stopMelody()`: Terminates active melody process.
- Connect `rumbleTriggered` signal so visual art in `ControllerArt.qml` pulses during melody notes.

- [ ] **Step 4: Expose IPC methods and verify via CLI test**

Add methods to `IpcHandler` target: `"omycontroller-service"`.  
Run: `python3 -c "import json; print('Service methods ready')"`  
Run: `npm test` or `node --test tests/model.test.js`.

- [ ] **Step 5: Commit**

```bash
git add Service.qml
git commit -m "feat(service): add haptic melody playback and audio diagnostic IPC to Service.qml"
```

---

### Task 5: JoyLab Retro Mario Platformer Component (`JoyLabGame.qml`)

**Files:**
- Create: `JoyLabGame.qml`

**Interfaces:**
- Consumes:
  - `property var liveButtons`
  - `property var liveAxes`
  - `property var axisMap`
  - `property string layout`
  - `signal runCompleted(var telemetry)`
  - `signal requestRumble(real weak, real strong, int ms)`
- Produces:
  - Interactive 60 FPS platformer arena with player physics, platforms, question mark coin blocks, hurdles, and flagpole.
  - Live HUD displaying: Latency (ms), Stick Circularity Error (%), Snapback count, Actuations.

- [ ] **Step 1: Create `JoyLabGame.qml` skeleton and canvas/physics loop**

Implement:
- Dimensions, dark-slate retro aesthetic, tile map (floor bricks, 3 floating coin blocks, 2 pipes, end flagpole).
- 60 FPS FrameAnimation / Timer (16ms) driving character physics:
  - `playerX`, `playerY`, `playerVx`, `playerVy`, `isGrounded`, `isJumping`.
  - Velocity driven by Left Stick X (`liveAxes[axisMap.leftX]`) or D-pad left/right buttons.
  - Variable jump height: triggered when jump button (Face Bottom: B for Switch, A for Xbox) pressed. Tap adds initial impulse; holding extends jump duration while gravity gradually pulls down.
  - Collision detection with floor and platforms.

- [ ] **Step 2: Add game mechanics: Coin blocks, flagpole, and haptic feedback**

Implement:
- Hitting a `?` coin block spawns a bouncy gold coin and emits `requestRumble(0.35, 0.15, 60)`.
- Reaching the flagpole plays victory animation, stops timer, emits `requestRumble(0.8, 0.4, 400)`, and signals `runCompleted(telemetry)`.

- [ ] **Step 3: Implement Live Hardware Telemetry HUD**

Implement:
- Overlay badge showing:
  - Instantaneous stick circularity error %: `Math.abs(Math.hypot(stickX, stickY) - 1.0) * 100`.
  - Live Input Delay (ms): measured delta from input event timestamp to render frame.
  - Snapback detector: records if stick rapidly snaps across center deadzone with magnitude > 0.12.
  - Actuations counter: total jumps, dashes, and coin pickups.
- "Finish & Benchmark Run" button to manually export current run stats.

- [ ] **Step 4: Verify QML syntax with `qmllint`**

Run: `qmllint JoyLabGame.qml`  
Expected: Clean syntax with no fatal errors.

- [ ] **Step 5: Commit**

```bash
git add JoyLabGame.qml
git commit -m "feat(joylab): create 60 FPS Mario platformer benchmark game component with live telemetry HUD"
```

---

### Task 6: 6-Tab Navigation, Tab 2 Audio/MIDI, Tab 4 JoyLab, Tab 5 Scorecard in `Panel.qml`

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Updates `currentTab`:
  - 0: Overview
  - 1: Sticks & Triggers
  - 2: Haptics & Audio
  - 3: Motion & Gyro
  - 4: JoyLab
  - 5: Device Specs & Performance Report
- Integrates `JoyLabGame` inside Tab 4.
- Integrates HD Rumble Melodic Player and Audio Jack Test Bench in Tab 2.
- Integrates Multi-Sector Performance Scorecard and Markdown exporter in Tab 5.

- [ ] **Step 1: Update Tab Bar models and indices in `Panel.qml`**

- Update `tabNames`:
  ```qml
  readonly property var tabNames: ["Overview", "Sticks & Triggers", "Haptics & Audio", "Motion", "JoyLab", "Device Specs"]
  ```
- Update side menu model icons:
  ```qml
  model: [
    { name: "Overview", icon: "🎮" },
    { name: "Sticks & Triggers", icon: "🎯" },
    { name: "Haptics & Audio", icon: "🔊" },
    { name: "Motion & Gyro", icon: "🧭" },
    { name: "JoyLab", icon: "🕹️" },
    { name: "Device Specs", icon: "📋" }
  ]
  ```

- [ ] **Step 2: Add HD Rumble Melodic Player & Audio Jack Test in Tab 2**

- Add Section: **"Nintendo HD Rumble Melodic Player"**:
  - Track buttons: Super Mario Bros, Legend of Zelda, Tetris, Pokémon, Coin, 1-Up.
  - Play / Stop controls with animated playing indicator.
- Add Section: **"Speaker & 3.5mm Audio Jack Diagnostic"**:
  - Sink info badge (showing detected sink name, e.g. DualSense Audio or Host Headphone Jack).
  - Test buttons: `◀ Left Channel`, `Right Channel ▶`, `▶ Stereo Ping`.
  - Animated VU output level meter.

- [ ] **Step 3: Integrate `JoyLabGame` in Tab 4**

- Add Tab 4 container hosting `JoyLabGame`:
  - Binds `liveButtons: root.liveButtons`, `liveAxes: root.liveAxes`, `axisMap: root.axisMap`, `layout: root.sel ? root.sel.layout : "generic"`.
  - Connects `requestRumble`: triggers `root.triggerRumble(w, s, ms)`.
  - Connects `runCompleted`: saves telemetry to `root.latestJoyLabStats` and displays completion toast.

- [ ] **Step 4: Integrate Multi-Sector Performance Scorecard in Tab 5**

- In Tab 5, add **"Hardware Performance Scorecard"**:
  - Overall Grade badge (S / A+ / A / B / C / D) with glowing playerColor rim.
  - 6-Sector breakdown grid:
    1. Sticks: Circularity error %, drift, snapbacks.
    2. Polling & Latency: Measured Hz, delay, jitter.
    3. Buttons & Triggers: Actuation count, ghosting, response.
    4. Haptics & Vibration: Motors ready, HD Rumble verified.
    5. IMU Motion: Gyro Hz, drift offset.
    6. Connectivity & Audio: Bus, battery, audio sink.
  - Gamepadla Model Reference comparison row (showing official database numbers).
  - Button: `"📋 Copy Markdown Diagnostic Report"` (writes formatted report to clipboard via `Quickshell.clipboard` or shell `wl-copy`).

- [ ] **Step 5: Run tests and linting**

Run: `node --test tests/model.test.js && bash tests/security.test.sh`  
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Panel.qml
git commit -m "feat(ui): update 6-tab deck layout, HD rumble player, audio test, JoyLab, and scorecard"
```

---

### Task 7: End-to-End Verification, Permissions, Linting & Live Hardware Run

**Files:**
- Modify/Verify: All project files, `tests/`
- Test: Full test suite, lint, permissions, shell restart

- [ ] **Step 1: Verify file permissions and POSIX compliance**

Run:
```bash
chmod 755 scripts/*.py scripts/*.sh tests/*.sh
chmod 644 *.qml *.js
```

- [ ] **Step 2: Run all unit, security, and catalog tests**

Run:
```bash
node --test tests/model.test.js
bash tests/security.test.sh
bash tests/scan.test.sh
```
Expected: All tests pass with 0 errors.

- [ ] **Step 3: Test live hardware and shell hot-reload**

Run:
```bash
omarchy-restart-shell
```
- Verify connected Nintendo Switch Pro controller responds to HD Rumble Mario track playback.
- Verify Audio Jack diagnostic generates Left/Right test tones.
- Verify Mario JoyLab platformer is playable at 60 FPS using the physical controller.
- Verify Multi-Sector Performance Scorecard generates accurate grades and copies markdown report.

- [ ] **Step 4: Final commit and summary**

```bash
git commit -am "feat: complete HD rumble MIDI, audio diagnostics, Mario JoyLab, and performance scorecard"
```
