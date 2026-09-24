# Design Specification: HD Rumble MIDI, Audio Diagnostics, Mario JoyLab Game & Multi-Sector Performance Scorecard

**Date**: 2026-09-24  
**Status**: Approved by User  
**Target Repository**: `MISTERNEGATIVE21/omycontroller`  

---

## 1. Executive Summary & Goals

This specification details the architecture, data flow, algorithms, and user experience for four major capabilities in **omycontroller**:
1. **HD Rumble Melodic MIDI Player & Haptics Customizer**: Modulate Linear Resonant Actuators (LRAs) on Nintendo Switch Pro and DualSense gamepads at musical frequencies to reproduce recognizable melodies (Super Mario Bros Overworld, Zelda Theme, Tetris Type A, Pokémon Battle), alongside rich waveform sculpting (pulse, sine, ramp, heartbeat, earthquake, coin, 1-up).
2. **Speaker & 3.5mm Audio Jack Diagnostics**: A PipeWire/ALSA test bench detecting controller-specific audio sinks (DualSense, Xbox Wireless Headset, USB DAC) with fallback to host audio for Nintendo Switch Pro, generating Left, Right, and Stereo test tones.
3. **Playable "Mario JoyLab" Performance Benchmark Game**: An integrated 60 FPS retro platformer test arena within the deck to measure real-time stick circularity, variable jump actuation latency, deadzone snapback, and tactile coin/flag haptics.
4. **Multi-Sector Hardware Performance Scorecard**: A comprehensive grading suite evaluating 6 core sectors (Sticks, Latency/Polling, Buttons/Triggers, Haptics, IMU Motion, Connectivity/Audio), benchmarking measured stats against official `GamepadlaCatalog` reference profiles, and offering one-click Markdown diagnostic report export.

---

## 2. Navigation & Layout Architecture

The Deck is expanded from 5 tabs to 6 distinct, accessible tabs:

| Tab Index | Name | Icon | Focus & Components |
| :---: | :--- | :---: | :--- |
| **0** | **Overview** | 🎮 | Silhouette vector art, quick connection badges, battery, Gamepadla photo match |
| **1** | **Sticks & Triggers** | 🎯 | Dual Circularity Radar (32 points), deadzone sliders, response curves, trigger travel |
| **2** | **Haptics & Audio** | 🔊 | LF/HF mixer, HD Rumble MIDI player, waveform presets, speaker & audio jack test bench |
| **3** | **Motion & Gyro** | 🧭 | 6-DOF artificial horizon, zero-rate bias calibration, telemetry velocity meters |
| **4** | **JoyLab** | 🕹️ | 60 FPS playable Mario platformer benchmark game with live telemetry HUD |
| **5** | **Device Specs** | 📋 | Sysfs hardware topology, Multi-Sector Performance Scorecard, Gamepadla comparison |

---

## 3. Subsystem Specifications

### Subsystem 1: HD Rumble MIDI & Haptics Engine

#### Acoustic Physics of LRAs & Force Feedback
Linear Resonant Actuators (LRAs) translate alternating force-feedback pulses into physical audio acoustic tones when driven at note frequencies:
$$f = 440 \times 2^{\frac{n - 69}{12}}$$
Peak LRA resonance is in the 120–320 Hz band; musical melodies are frequency-mapped so high frequencies use harmonic acoustic modulation and low frequencies produce tactile rumble.

#### Script Architecture: `scripts/haptic_midi.py`
- Executable Python 3 script using `python-evdev` `EV_FF` / `ff.Rumble`.
- **CLI Usage**:
  ```bash
  python3 scripts/haptic_midi.py <event-node> <track-name> [--volume 0.0-1.0] [--repeat N]
  ```
- **Track Library**:
  - `mario`: Super Mario Bros Ground Theme (Intro + Main theme groove)
  - `zelda`: The Legend of Zelda Overworld Theme
  - `tetris`: Tetris Type A (Korobeiniki melody)
  - `pokemon`: Pokémon Red/Blue Wild Pokemon Battle intro
  - `coin`: Two-tone coin pickup (B5 -> E6)
  - `oneup`: Six-note 1-Up fanfare
- **Timing & Performance**: Pre-uploads rumble effects to avoid kernel allocations in the play loop, using `time.perf_counter()` for sub-millisecond note precision.
- **Safety**: Hard timeout of 15 seconds per execution to prevent voice coil / LRA overheating.

#### QML & Service Integration
- `Service.qml`: Exposes `playMelody(id, track, volume)` and `stopMelody()`.
- `Panel.qml` (Tab 2):
  - Track dropdown selector and Play/Stop button.
  - Interactive wave presets: Sine Sweep, Engine Rev, Earthquake, Heartbeat, Coin, 1-Up.
  - Synchronized visual haptic pulsing on `ControllerArt.qml`.

---

### Subsystem 2: Speaker & 3.5mm Audio Jack Diagnostic Bench

#### Architecture
- Controllers with onboard DACs (DualSense, Xbox Wireless with DAC) appear in PipeWire / ALSA as sinks.
- Nintendo Switch Pro controllers do not have an onboard DAC under the Linux `hid-nintendo` driver; the Smart Audio Probe automatically tests the controller when a sink is present and routes to the system default headphone/speaker sink when absent.

#### Script Architecture: `scripts/audio_test.py`
- **CLI Usage**:
  ```bash
  python3 scripts/audio_test.py probe                          # Output JSON with detected sinks
  python3 scripts/audio_test.py play <left|right|stereo> [sink] # Play pure PCM test tone
  ```
- **Tone Generation**: Native Python stdlib `wave` + `struct` generating clean sinusoidal 16-bit PCM (440 Hz Left, 880 Hz Right, or alternating Stereo Ping) piped to PipeWire (`pw-cat -p`) or PulseAudio (`paplay`) or ALSA (`aplay`).
- **Safety**: Peak amplitude normalized to 0.75 max to avoid ear/equipment damage.

#### QML & Service Integration
- `Service.qml`: `probeAudioDevices()`, `playAudioTone(channel, sink)`.
- `Panel.qml` (Tab 2):
  - Audio Hardware Status Banner (`[Sink Name · Sample Rate · Channels]`).
  - Buttons: `◀ Test Left`, `Test Right ▶`, `▶ Test Stereo Ping`.
  - Animated dual-channel VU audio meter.

---

### Subsystem 3: Playable "Mario JoyLab" Platformer Performance Game

#### Architecture: `JoyLabGame.qml`
- Standalone QML component running inside Tab 4 at 60 FPS.
- **Game Elements**:
  - Retro pixel bricks, question mark coin blocks, warp pipe obstacles, and finish flagpole.
  - Player sprite with walk/run animation and variable jump height.
- **Physics Engine**:
  - Horizontal movement driven by Left Stick $X \in [-1.0, 1.0]$ or D-Pad.
  - Variable jump height driven by Face Bottom (Nintendo B, Xbox A, PS Cross): tap = small hop, hold = full jump. Gravity $g = 0.8\text{ px/frame}^2$.
  - Sprint / Dash: Right Trigger or Face East button increases top speed.
  - Gyro tilt: Tilting the controller tilts floating balance bridges in the course.
- **Tactile Haptics**:
  - Coin pickup: 50 ms crisp LRA tick (`triggerRumble(0.35, 0.15, 50)`).
  - High jump landing: thud vibration.
  - Flagpole completion: victory HD rumble fanfare.
- **Real-Time Telemetry HUD**:
  - Live latency (ms) and polling rate (Hz).
  - Instantaneous stick circularity error (%) and deflection angle.
  - Snapback detector: records reverse overshoot on stick release.
  - Actuation counter: jumps, dashes, coins collected, dropped inputs.
- **Scorecard Hand-off**: Clicking "Finish & Analyze Run" passes telemetry directly to Tab 5's Multi-Sector Performance Scorecard.

---

### Subsystem 4: Multi-Sector Hardware Performance Scorecard

#### Scoring Engine in `GamepadModel.js`
Evaluates the connected controller across 6 standardized hardware sectors:
1. **Stick Precision & Circularity**: % Error vs ideal circle ($R=1.0$), cardinal vs diagonal variance, center drift $(X_0, Y_0)$, snapback count.
2. **Polling Rate & Latency**: Measured Polling Hz, average latency (ms), latency jitter (ms).
3. **Button Actuation & Switch Health**: Ghosting check, actuation latency, debounce consistency.
4. **Haptics & Vibration Engine**: LF/HF motor readiness, HD rumble agility, adaptive trigger readiness.
5. **6-DOF IMU Motion**: Gyro sampling rate (Hz), zero-rate bias offset (deg/s), accelerometer stationary noise floor.
6. **Connectivity & Audio Health**: Bus type (USB/BT/Dongle), battery level %, audio sink latency and readiness.

#### Model-Specific Gamepadla Benchmark Comparison
- Queries `GamepadlaCatalog.js` for the detected model (e.g. Nintendo Switch Pro).
- Displays measured metrics alongside official Gamepadla lab measurements:
  - *Circularity Error*: Measured vs Gamepadla database reference.
  - *Polling Rate*: Measured Hz vs Gamepadla verified protocol limit.
  - *Latency*: Measured ms vs Gamepadla lowest achievable delay.

#### Scorecard UI & Export
- Located in Tab 5 (Device Specs).
- Displays Overall Performance Tier: **S / A+ / A / B / C / D**.
- Six sector score meters with pass/warn/fail indicators.
- **"Copy Markdown Report" Button**: Exports a clean, structured diagnostic report to the system clipboard.

---

## 4. Testing & Verification Plan

1. **Unit Tests (`tests/model.test.js`)**:
   - Validate performance scorecard calculation and grading algorithms.
   - Validate MIDI note-frequency formulas and track array integrity.
   - Validate audio device classification and fallback logic.
2. **Security & Validation Tests (`tests/security.test.sh`)**:
   - Validate input argument checking in `scripts/haptic_midi.py`.
   - Validate input argument checking in `scripts/audio_test.py`.
   - Validate path traversal and character device checks on event nodes.
3. **QML Lint & Static Verification**:
   - Run `qmllint` on `JoyLabGame.qml`, `Panel.qml`, `Service.qml`, and `ControllerArt.qml`.
4. **Live Hardware Verification**:
   - Hot-reload via `omarchy-restart-shell`.
   - Test HD Rumble playback on connected Nintendo Switch Pro Controller (`/dev/input/event30`).
   - Test audio tone playback.
   - Play Mario JoyLab platformer using physical gamepad buttons and sticks.
   - Generate and verify Multi-Sector Performance Scorecard.
