import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GamepadModel.js" as GamepadModel
import "GamepadlaCatalog.js" as GamepadlaCatalog
import "."

// omycontroller — Panel.qml
//
// 5-tab Segmented Pro Control Deck popout for Omarchy:
//   1. Header with slot selector (P1..P4) and Simulator toggle
//   2. Tab 1: Overview (model-accurate vector silhouette, status chips with Gamepadla SVGs)
//   3. Tab 2: Sticks & Triggers (Dual CircularityRadar, inner/outer deadzones, curve presets, triggers)
//   4. Tab 3: Haptics Studio (LF/HF rumble mixer, rhythm test patterns, DualSense trigger tuning)
//   5. Tab 4: Motion & Gyro (6-DOF Artificial Horizon, telemetry velocity meters, drift calibration)
//   6. Tab 5: Device Specs (Full Gamepadla hardware diagnostics sheet & certification badges)
//
// Theme-aware styling utilizing qs.Commons (Color, Style) and qs.Ui.

Panel {
  id: root
  moduleName: "omycontroller"
  ipcTarget: "omycontroller"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // ------------------------------------------------------------ service
  readonly property var svc: {
    if (hostWidget && hostWidget.svc) return hostWidget.svc
    if (bar && bar.shell && typeof bar.shell.serviceFor === "function") {
      var s = bar.shell.serviceFor("omycontroller")
      if (s) return s
      return bar.shell.serviceFor("quatro.gamepad")
    }
    return null
  }
  readonly property var pads: svc ? svc.deviceList : []
  readonly property var stats: (svc && svc.stats) ? svc.stats : computeFallbackStats()

  function computeFallbackStats() {
    return {
      hz: 0,
      pollingRate: 0,
      avg: 0,
      avgMs: 0,
      min: 0,
      minMs: 0,
      max: 0,
      maxMs: 0,
      jitter: 0,
      formattedHz: "0 Hz",
      label: "idle"
    }
  }

  // ------------------------------------------------------------ settings
  readonly property bool showLatency: hostWidget ? hostWidget.setting("showLatency", true) !== false : true
  readonly property int lowBatteryThreshold: {
    var v = hostWidget ? hostWidget.setting("lowBatteryThreshold", 15) : 15
    var n = Number(v)
    return isFinite(n) ? n : 15
  }
  property string menuPosition: hostWidget ? hostWidget.setting("menuPosition", "left") : "left"
  readonly property bool isSideMenu: menuPosition === "left" || menuPosition === "right"

  // ------------------------------------------------------------ selection
  property string selectedId: ""
  readonly property var sel: {
    for (var i = 0; i < pads.length; i++) {
      if (pads[i].id === selectedId) return pads[i]
    }
    return pads.length > 0 ? pads[0] : null
  }
  readonly property color playerColor: sel ? GamepadModel.playerColor(sel.slot, Color) : Color.accent

  // ------------------------------------------------- gamepadla catalog match
  // Best gamepadla.com entry for the selected pad (by classified model +
  // maker), driving the deck photo surface and the benchmark sheet rows.
  // null → generic fallback rendering.
  readonly property var matched: sel ? GamepadlaCatalog.find(sel.modelLabel || sel.name, sel.maker) : null
  readonly property string matchedImage: matched ? Qt.resolvedUrl(GamepadlaCatalog.imagePath(matched.entry)) : ""

  readonly property string matchTitle: matched
    ? (matched.entry.n + (matched.entry.b ? " · " + matched.entry.b : "")) : ""
  readonly property string matchVerdict: matched
    ? ("benchmark verified" + (matched.entry.plats && matched.entry.plats.length
        ? " for " + matched.entry.plats.slice(0, 3).join(" · ") : "") +
      " · " + Math.round(matched.score * 100) + "% match")
    : ""
  readonly property string matchMetrics: matched
    ? (GamepadlaCatalog.bestLatency(matched.entry)
        ? "best " + GamepadlaCatalog.bestLatency(matched.entry).mode +
          " " + GamepadlaCatalog.bestLatency(matched.entry).ms.toFixed(2) + " ms" : "") +
      (matched.entry.avg ? " · avg " + Number(matched.entry.avg).toFixed(1) + " ms" : "") +
      (matched.entry.poll ? " · poll " + Math.round(Number(matched.entry.poll)) + " Hz" : "")
    : ""

  // Live state mirrors (copied on every event for instant re-render)
  property var liveButtons: ({})
  property var liveAxes: []
  property var liveGyro: null
  readonly property var axisMap: GamepadModel.axesMap(root.sel ? root.sel.layout : "generic", root.liveAxes ? root.liveAxes.length : 0, root.sel ? root.sel.axisNames : [])


  // Live rumble visual haptic state & duration
  property bool rumbleActive: false
  property real rumbleWeak: 0.0
  property real rumbleStrong: 0.0
  property int rumbleDurationMs: 1200

  // Live LED lightbar state & PlayStation presets
  property color currentLedColor: (root.sel && root.sel.profile && root.sel.profile.ledColor) ? root.sel.profile.ledColor : "#0066ff"
  property int ledR: GamepadModel.hexToRgb(root.currentLedColor).r
  property int ledG: GamepadModel.hexToRgb(root.currentLedColor).g
  property int ledB: GamepadModel.hexToRgb(root.currentLedColor).b

  // Live capacitive touchpad diagnostics state
  property var touchpadState: ({
    active: false,
    fingers: [],
    trails: [],
    pressure: 0.85,
    zone: "Center Surface"
  })

  function handleTouchpadInteraction(normX, normY, pressed) {
    var x = Math.max(0, Math.min(1.0, normX))
    var y = Math.max(0, Math.min(1.0, normY))
    var zoneName = (y > 0.8) ? (x < 0.5 ? "Left Click Zone" : "Right Click Zone") : "Center Surface"
    var trails = root.touchpadState.trails ? root.touchpadState.trails.slice() : []
    if (pressed) {
      trails.push({ x: x, y: y, ts: Date.now() })
      if (trails.length > 35) trails.shift()
    }
    root.touchpadState = {
      active: pressed,
      fingers: pressed ? [{ id: 0, x: x, y: y, pressed: true }] : [],
      trails: trails,
      pressure: pressed ? 0.90 : 0.0,
      zone: zoneName
    }
  }

  function simulateGesture(gestureType) {
    if (gestureType === "tap") {
      root.touchpadState = {
        active: true,
        fingers: [{ id: 0, x: 0.5, y: 0.5, pressed: true }],
        trails: [{ x: 0.5, y: 0.5, ts: Date.now() }],
        pressure: 0.95,
        zone: "Center Surface"
      }
      gestureTimer.interval = 350
      gestureTimer.restart()
    } else if (gestureType === "twofinger") {
      root.touchpadState = {
        active: true,
        fingers: [
          { id: 0, x: 0.70, y: 0.88, pressed: true },
          { id: 1, x: 0.85, y: 0.88, pressed: true }
        ],
        trails: [{ x: 0.70, y: 0.88, ts: Date.now() }, { x: 0.85, y: 0.88, ts: Date.now() }],
        pressure: 0.95,
        zone: "Right Click Zone"
      }
      gestureTimer.interval = 400
      gestureTimer.restart()
    } else if (gestureType === "pinch") {
      root.touchpadState = {
        active: true,
        fingers: [
          { id: 0, x: 0.35, y: 0.40, pressed: true },
          { id: 1, x: 0.65, y: 0.60, pressed: true }
        ],
        trails: [
          { x: 0.25, y: 0.30, ts: Date.now() },
          { x: 0.35, y: 0.40, ts: Date.now() },
          { x: 0.75, y: 0.70, ts: Date.now() },
          { x: 0.65, y: 0.60, ts: Date.now() }
        ],
        pressure: 0.85,
        zone: "Multi-Touch Pinch"
      }
      gestureTimer.interval = 600
      gestureTimer.restart()
    } else if (gestureType === "swipe") {
      root.touchpadState = {
        active: true,
        fingers: [{ id: 0, x: 0.85, y: 0.50, pressed: true }],
        trails: [
          { x: 0.98, y: 0.50, ts: Date.now() },
          { x: 0.92, y: 0.50, ts: Date.now() },
          { x: 0.85, y: 0.50, ts: Date.now() }
        ],
        pressure: 0.90,
        zone: "Edge Swipe Inward"
      }
      gestureTimer.interval = 500
      gestureTimer.restart()
    } else if (gestureType === "clear") {
      root.touchpadState = {
        active: false,
        fingers: [],
        trails: [],
        pressure: 0.0,
        zone: "Ready"
      }
    }
  }

  Timer {
    id: gestureTimer
    repeat: false
    onTriggered: {
      if (root.touchpadState && root.touchpadState.active) {
        root.touchpadState.active = false
        if (root.touchpadState.fingers) {
          for (var i = 0; i < root.touchpadState.fingers.length; i++) {
            root.touchpadState.fingers[i].pressed = false
          }
        }
      }
    }
  }

  function applyLedColor(r, g, b) {
    if (!root.svc) return
    var targetId = root.sel ? root.sel.id : "js0"
    root.svc.setLed(targetId, r, g, b)
    root.currentLedColor = GamepadModel.rgbToHex(r, g, b)
    root.ledR = r
    root.ledG = g
    root.ledB = b
  }

  Timer {
    id: rumbleDecayTimer
    interval: 500
    repeat: false
    onTriggered: {
      root.rumbleActive = false
      root.rumbleWeak = 0.0
      root.rumbleStrong = 0.0
    }
  }

  function refreshLive() {
    if (!sel) { liveButtons = ({}); liveAxes = []; liveGyro = null; return }
    var b = {}
    for (var k in sel.buttons) b[k] = sel.buttons[k]
    liveButtons = b
    liveAxes = (sel.axes || []).slice()
    var g = sel.gyro
    liveGyro = g ? {
      ax: g.ax, ay: g.ay, az: g.az,
      gx: g.gx, gy: g.gy, gz: g.gz,
      pitch: g.pitch, roll: g.roll, yaw: g.yaw,
      afs: g.afs, gfs: g.gfs
    } : null
  }

  function select(id) {
    selectedId = String(id || "")
    refreshLive()
  }

  onSelChanged: {
    root.refreshLive()
  }

  Connections {
    target: svc
    function onLiveUpdated(id) {
      if (!root.sel || id === root.sel.id || id === root.selectedId) {
        root.refreshLive()
      }
    }
    function onDevicesChanged() {
      if ((!root.selectedId || !root.sel) && root.pads.length > 0) {
        root.select(root.pads[0].id)
      } else if (root.sel) {
        root.refreshLive()
      }
    }
    function onActionResult(message) {
      root.actionMsg = String(message || "")
    }
    function onRumbleTriggered(id, weak, strong, ms) {
      if (!root.sel || id === root.sel.id || id === "sim0") {
        root.rumbleWeak = weak
        root.rumbleStrong = strong
        root.rumbleActive = true
        rumbleDecayTimer.interval = Math.max(100, ms || 500)
        rumbleDecayTimer.restart()
      }
    }
    function onLedColorChanged(id, r, g, b, hex) {
      if (!root.sel || id === root.sel.id || id === root.selectedId) {
        root.currentLedColor = hex
        root.ledR = r
        root.ledG = g
        root.ledB = b
      }
    }
  }

  IpcHandler {
    target: "omycontroller-panel"

    function toggleDemo(): string {
      if (root.svc) root.svc.toggleDemo()
      return "toggled"
    }

    function setTab(tabIdx: int): string {
      root.currentTab = tabIdx
      return "tab set"
    }

    function setRemapMode(active: bool): string {
      root.remapModeActive = active
      return "remapMode set"
    }

    function testOpenModal(role: string, idx: int, label: string): string {
      remapModal.open(role, idx, label)
      return "modal opened"
    }

    function closeModal(): string {
      remapModal.close()
      return "modal closed"
    }

    function getLiveState(): string {
      return JSON.stringify({
        selectedId: root.selectedId,
        selId: root.sel ? root.sel.id : null,
        layout: root.sel ? root.sel.layout : null,
        buttonPreset: root.sel ? (root.sel.buttonPreset || (root.sel.profile && root.sel.profile.buttonPreset)) : null,
        buttons: root.liveButtons,
        axes: root.liveAxes,
        currentTab: root.currentTab,
        padsCount: root.pads.length,
        rumbleActive: root.rumbleActive
      })
    }

    function scrollContentY(y: int): string {
      tabFlick.contentY = y
      return "scrolled"
    }

    function applyRemap(role: string, targetIdx: int): string {
      root.applyButtonRemap(role, targetIdx)
      return "remapped"
    }
  }

  onOpenedChanged: {
    if (!opened) {
      rhythmTimer.stop()
      rhythmSteps = []
      rhythmStepIdx = 0
    }
  }

  Component.onCompleted: {
    if (pads.length > 0) selectedId = pads[0].id
  }

  // ------------------------------------------------------------ navigation
  property int currentTab: 0
  readonly property var tabNames: ["Overview", "Sticks & Triggers", "Haptics & Audio", "Motion & Gyro", "JoyLab", "Device Specs"]

  // ------------------------------------------------------------ actions & tuning
  property string actionMsg: ""
  property real lfMixer: 0.70
  property real hfMixer: 0.50
  property string selectedTriggerMode: "Rigid"
  property real triggerStartPos: 0.15
  property real triggerForce: 0.85

  // JoyLab & Scorecard Telemetry
  property var latestJoyLabStats: null
  readonly property var scorecard: GamepadModel.computePerformanceScorecard(root.sel, root.stats, root.latestJoyLabStats)
  property string selectedMidiTrack: "mario"
  property real midiVolume: 0.85
  property string activeAudioTest: ""

  // Haptics rhythm runner
  property var rhythmSteps: []
  property int rhythmStepIdx: 0

  Timer {
    id: rhythmTimer
    interval: 100
    repeat: false
    onTriggered: root.executeNextRhythmStep()
  }

  function playRhythm(patternName) {
    if (patternName === "pulse") {
      rhythmSteps = [
        { w: 0.7, s: 0.9, d: 200 },
        { w: 0.0, s: 0.0, d: 120 },
        { w: 0.7, s: 0.9, d: 200 },
        { w: 0.0, s: 0.0, d: 120 },
        { w: 0.8, s: 1.0, d: 220 },
        { w: 0.0, s: 0.0, d: 120 },
        { w: 0.9, s: 1.0, d: 250 }
      ]
    } else if (patternName === "heartbeat") {
      rhythmSteps = [
        { w: 0.8, s: 0.5, d: 150 },
        { w: 0.0, s: 0.0, d: 120 },
        { w: 1.0, s: 0.9, d: 280 },
        { w: 0.0, s: 0.0, d: 350 },
        { w: 0.8, s: 0.5, d: 150 },
        { w: 0.0, s: 0.0, d: 120 },
        { w: 1.0, s: 1.0, d: 330 }
      ]
    } else if (patternName === "ramp") {
      rhythmSteps = [
        { w: 0.20, s: 0.25, d: 250 },
        { w: 0.40, s: 0.45, d: 250 },
        { w: 0.65, s: 0.70, d: 300 },
        { w: 0.85, s: 0.90, d: 300 },
        { w: 1.00, s: 1.00, d: 350 }
      ]
    } else if (patternName === "burst") {
      rhythmSteps = [
        { w: 1.0, s: 1.0, d: 1500 }
      ]
    }
    rhythmStepIdx = 0
    executeNextRhythmStep()
  }

  function executeNextRhythmStep() {
    if (rhythmStepIdx >= rhythmSteps.length) return
    var step = rhythmSteps[rhythmStepIdx]
    rhythmStepIdx++
    if (step.w > 0 || step.s > 0) {
      root.triggerRumble(step.w, step.s, step.d)
    }
    if (rhythmStepIdx < rhythmSteps.length) {
      rhythmTimer.interval = step.d + 15
      rhythmTimer.restart()
    }
  }

  function triggerRumble(w, s, ms) {
    if (!root.svc || !root.sel) return
    root.svc.rumble(root.sel.id, w, s, ms)
  }

  function playMelody(track, vol) {
    if (!root.svc || !root.sel) return
    root.svc.playMelody(root.sel.id, track, vol)
  }

  function stopMelody() {
    if (!root.svc) return
    root.svc.stopMelody()
  }

  function playAudioTone(channel, sink) {
    if (!root.svc) return
    root.activeAudioTest = channel
    root.svc.playAudioTone(channel, sink)
    audioToneResetTimer.restart()
  }

  function copyReportToClipboard() {
    var md = GamepadModel.exportMarkdownReport(root.sel, root.scorecard)
    clipProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy || printf '%s' \"$1\" | xclip -selection clipboard", "sh", md]
    clipProc.running = true
    if (root.svc) root.svc.actionResult("Diagnostic report copied to clipboard!")
  }

  Process {
    id: clipProc
    running: false
  }

  Timer {
    id: audioToneResetTimer
    interval: 900
    repeat: false
    onTriggered: root.activeAudioTest = ""
  }

  function applyTriggerEffect(start, force) {
    if (!root.svc || !root.sel) return
    var s = (start !== undefined && isFinite(Number(start))) ? Number(start) : root.triggerStartPos
    var f = (force !== undefined && isFinite(Number(force))) ? Number(force) : root.triggerForce
    var mode = root.selectedTriggerMode.toLowerCase()
    if (root.sel.id === "sim0") {
      root.actionMsg = "DualSense trigger effect [" + root.selectedTriggerMode + "] (start " + Math.round(s * 100) + "%, force " + Math.round(f * 100) + "%) simulated on " + root.sel.modelLabel
      return
    }
    root.svc.setTriggers(root.sel.id, mode, mode, s, f)
    root.actionMsg = "DualSense trigger effect [" + root.selectedTriggerMode + "] applied (start " + Math.round(s * 100) + "%, force " + Math.round(f * 100) + "%)"
  }

  function setDz(key, value) {
    if (!root.sel || !root.svc) return
    root.svc.setDeadzone(root.sel.id, key, value)
    root.refreshLive()
  }

  function setProfileVal(key, value) {
    if (!root.sel || !root.svc) return
    var obj = {}
    obj[key] = value
    if (typeof root.svc.storeProfile === "function") {
      root.svc.storeProfile(root.sel, obj)
    } else {
      if (!root.sel.profile) root.sel.profile = {}
      root.sel.profile[key] = value
    }
    root.refreshLive()
  }

  property bool remapModeActive: false

  function applyButtonRemap(role, targetIdx) {
    if (!root.sel) return
    var cur = {}
    if (root.sel.profile && root.sel.profile.buttonMap) {
      for (var k in root.sel.profile.buttonMap) {
        cur[k] = root.sel.profile.buttonMap[k]
      }
    }
    if (targetIdx === undefined || targetIdx === null || targetIdx < -1) {
      delete cur[role]
    } else {
      cur[role] = targetIdx
    }
    root.setProfileVal("buttonMap", cur)
  }

  function resetAllRemaps() {
    if (!root.sel) return
    root.setProfileVal("buttonMap", {})
    root.setProfileVal("remapPreset", "standard")
  }

  function handleVirtualButton(idx, pressed) {
    if (idx < 0) return
    var b = Object.assign({}, root.liveButtons)
    if (pressed) {
      b[idx] = true
    } else {
      delete b[idx]
    }
    root.liveButtons = b
  }

  function handleVirtualDpad(dir, pressed) {
    var axes = (root.liveAxes || []).slice()
    while (axes.length < 8) axes.push(0)
    var layout = root.sel ? root.sel.layout : "xbox"
    var axisNames = root.sel ? root.sel.axisNames : []
    var am = GamepadModel.axesMap(layout, axes.length, axisNames)
    if (dir === "up") {
      if (am.hatY >= 0 && am.hatY < axes.length) axes[am.hatY] = pressed ? -1.0 : 0.0
    } else if (dir === "down") {
      if (am.hatY >= 0 && am.hatY < axes.length) axes[am.hatY] = pressed ? 1.0 : 0.0
    } else if (dir === "left") {
      if (am.hatX >= 0 && am.hatX < axes.length) axes[am.hatX] = pressed ? -1.0 : 0.0
    } else if (dir === "right") {
      if (am.hatX >= 0 && am.hatX < axes.length) axes[am.hatX] = pressed ? 1.0 : 0.0
    }
    root.liveAxes = axes
  }

  function handleVirtualStick(side, sx, sy, active) {
    var axes = (root.liveAxes || []).slice()
    while (axes.length < 6) axes.push(0)
    var layout = root.sel ? root.sel.layout : "xbox"
    var axisNames = root.sel ? root.sel.axisNames : []
    var am = GamepadModel.axesMap(layout, axes.length, axisNames)
    if (side === "l") {
      if (am.lx >= 0 && am.lx < axes.length) axes[am.lx] = sx
      if (am.ly >= 0 && am.ly < axes.length) axes[am.ly] = sy
    } else {
      if (am.rx >= 0 && am.rx < axes.length) axes[am.rx] = sx
      if (am.ry >= 0 && am.ry < axes.length) axes[am.ry] = sy
    }
    root.liveAxes = axes
  }

  function handleVirtualTrigger(side, val) {
    var axes = (root.liveAxes || []).slice()
    while (axes.length < 6) axes.push(0)
    var layout = root.sel ? root.sel.layout : "xbox"
    var axisNames = root.sel ? root.sel.axisNames : []
    var am = GamepadModel.axesMap(layout, axes.length, axisNames)
    var isXbox = layout === "xbox"
    var raw = isXbox ? (val * 2.0 - 1.0) : val
    if (side === "l") {
      if (am.lt >= 0 && am.lt < axes.length) axes[am.lt] = raw
    } else {
      if (am.rt >= 0 && am.rt < axes.length) axes[am.rt] = raw
    }
    root.liveAxes = axes
  }

  function stickX(side) {
    var axes = root.liveAxes
    var layout = root.sel ? root.sel.layout : "xbox"
    var axisNames = root.sel ? root.sel.axisNames : []
    var axisMap = GamepadModel.axesMap(layout, axes ? axes.length : 0, axisNames)
    var idx = side === "l" ? axisMap.lx : axisMap.rx
    if (idx === -1 || !axes || idx >= axes.length) return 0
    var v = Number(axes[idx])
    return isFinite(v) ? v : 0
  }

  function stickY(side) {
    var axes = root.liveAxes
    var layout = root.sel ? root.sel.layout : "xbox"
    var axisNames = root.sel ? root.sel.axisNames : []
    var axisMap = GamepadModel.axesMap(layout, axes ? axes.length : 0, axisNames)
    var idx = side === "l" ? axisMap.ly : axisMap.ry
    if (idx === -1 || !axes || idx >= axes.length) return 0
    var v = Number(axes[idx])
    if (!isFinite(v)) return 0
    var p = root.sel && root.sel.profile ? root.sel.profile : null
    if (p && ((side === "l" && p.invertLY) || (side === "r" && p.invertRY))) {
      v = -v
    }
    return v
  }

  function dzFor(side) {
    var p = root.sel && root.sel.profile ? root.sel.profile : null
    var v = p ? Number(side === "l" ? p.stickL : p.stickR) : 0.10
    return isFinite(v) ? v : 0.10
  }

  function triggerNorm(side) {
    var layout = root.sel ? root.sel.layout : "xbox"
    var tables = GamepadModel.buttonTables(layout, root.sel ? root.sel.profile : null)
    var btnPressed = side === "l"
      ? !!(root.liveButtons && tables.triggerL >= 0 && root.liveButtons[tables.triggerL])
      : !!(root.liveButtons && tables.triggerR >= 0 && root.liveButtons[tables.triggerR])
    if (btnPressed) return 1.0

    var axes = root.liveAxes
    if (!axes || axes.length === 0) return 0.0
    var axisNames = root.sel ? root.sel.axisNames : []
    var axisMap = GamepadModel.axesMap(layout, axes ? axes.length : 0, axisNames)
    var idx = side === "l" ? axisMap.lt : axisMap.rt
    if (idx === -1 || idx >= axes.length || !isFinite(Number(axes[idx]))) return 0.0
    return GamepadModel.triggerNorm(layout, Number(axes[idx]))
  }

  // ------------------------------------------------------------ lifecycle
  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }
  function closeForPopoutSwitch() {
    root.close()
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") {
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    }
    return false
  }

  // ============================================================ layout
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.isSideMenu ? Style.space(600) : Style.space(480))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---------------------------------------------------- 1. Header
        Item {
          width: parent.width
          height: Math.max(headerRow.implicitHeight, headerRightRow.implicitHeight)

          Row {
            id: headerRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - headerRightRow.width - Style.space(8))
            clip: true
            spacing: Style.space(8)

            Text {
              text: "OMYCONTROLLER"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 2
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: countLabel.implicitWidth + Style.space(10)
              height: Style.font.caption + Style.space(6)
              radius: height / 2
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)

              Text {
                id: countLabel
                anchors.centerIn: parent
                text: root.pads.length === 0
                  ? "no pads"
                  : (root.pads.length + (root.pads.length === 1 ? " pad" : " pads"))
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Right Controls: Simulator & Rescan Hardware Buttons
          Row {
            id: headerRightRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              id: simBtn
              anchors.verticalCenter: parent.verticalCenter
              text: (root.svc && root.svc.simulatorActive) ? "⏹ Stop Sim" : "▶ Simulator"
              focusable: true
              foreground: root.barForeground
              accent: Color.accent
              onClicked: {
                if (root.svc) root.svc.toggleDemo()
              }
            }

            Button {
              id: rescanBtn
              anchors.verticalCenter: parent.verticalCenter
              text: "↻ Rescan"
              focusable: true
              foreground: root.barForeground
              accent: Color.accent
              onClicked: {
                if (root.svc) root.svc.runScan()
              }
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ---------------------------------------------------- Empty State
        Column {
          visible: root.pads.length === 0
          width: parent.width
          spacing: Style.space(10)

          Item { height: Style.space(4); width: 1 }

          // Preview Chassis Card
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(24)
            height: Style.space(195)
            radius: Style.cornerRadius
            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.03)
            border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
            border.width: 1

            ControllerArt {
              anchors.centerIn: parent
              mini: false
              layout: "xbox"
              playerColor: Color.accent
              ledColor: root.currentLedColor
              touchpadState: root.touchpadState
              buttons: root.liveButtons
              axes: root.liveAxes
              width: Style.space(280)
              height: Style.space(170)
              showLabels: true

              onTouchpadInteracted: function(tx, ty, pressed) {
                root.handleTouchpadInteraction(tx, ty, pressed)
              }
              onButtonClicked: function(index, pressed) {
                root.handleVirtualButton(index, pressed)
              }
              onStickMoved: function(side, sx, sy) {
                root.handleVirtualStick(side, sx, sy, true)
              }
              onStickReleased: function(side) {
                root.handleVirtualStick(side, 0, 0, false)
              }
              onTriggerMoved: function(side, val) {
                root.handleVirtualTrigger(side, val)
              }
            }
          }

          // Standby Wireless Dongle Callout Card
          Rectangle {
            visible: Boolean(root.svc && root.svc.standbyDongle)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(24)
            height: Style.space(64)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.40)
            border.width: 1

            Row {
              anchors.centerIn: parent
              spacing: Style.space(12)

              Text {
                text: "📡"
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  text: (root.svc && root.svc.standbyDongle) ? (root.svc.standbyDongle.name + " Connected") : "Wireless Adapter Connected"
                  color: Color.accent
                  font.bold: true
                  font.pixelSize: Style.font.body
                }

                Text {
                  text: "Turn ON your controller (press Home / Power) to link wirelessly"
                  color: root.barForeground
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (root.svc && root.svc.standbyDongle) ? "Wireless Receiver Ready" : "No Gamepads Detected"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            width: parent.width - Style.space(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: (root.svc && root.svc.standbyDongle)
              ? ("A 2.4G wireless USB receiver (" + root.svc.standbyDongle.name + ") is detected. Turn ON your controller or press the Home button to link wirelessly.")
              : "Plug in an Xbox, PlayStation, Switch Pro, or generic controller via USB cable, Bluetooth, or wireless adapter. Up to 4 players supported with real-time diagnostics, circularity radar, haptics, and 6-DOF gyro."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Button {
              text: (root.svc && root.svc.simulatorActive) ? "⏹ Stop Sim" : "▶ Start Simulator Bench"
              focusable: true
              foreground: root.barForeground
              accent: Color.accent
              onClicked: if (root.svc) root.svc.toggleDemo()
            }

            Button {
              text: "↻ Rescan Hardware"
              focusable: true
              foreground: root.barForeground
              accent: Color.accent
              onClicked: if (root.svc) root.svc.runScan()
            }
          }

          Item { height: Style.space(6); width: 1 }
        }

        // ---------------------------------------------------- Active Device Deck
        Column {
          visible: root.pads.length > 0
          width: parent.width
          spacing: Style.space(8)

          // Slot Selector (P1..P4 Pills)
          Row {
            visible: !root.isSideMenu
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: 4

              delegate: Rectangle {
                id: slotPill
                required property int index
                readonly property var pad: root.pads.length > index ? root.pads[index] : null
                readonly property bool isSel: root.sel && pad && pad.id === root.sel.id
                readonly property color slotColor: GamepadModel.playerColor(index + 1, Color)

                width: (parent.width - 3 * Style.space(6)) / 4
                height: Style.space(36)
                radius: Math.max(4, Style.cornerRadius)
                color: isSel
                  ? Qt.rgba(slotColor.r, slotColor.g, slotColor.b, 0.16)
                  : slotMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                  : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.03)
                border.color: isSel ? slotColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                border.width: isSel ? 1.5 : 1

                Behavior on color { ColorAnimation { duration: 80 } }

                MouseArea {
                  id: slotMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: slotPill.pad ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: if (slotPill.pad) root.select(slotPill.pad.id)
                }

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  spacing: Style.space(4)

                  // Slot player color dot
                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7; radius: 3.5
                    color: slotPill.pad ? slotPill.slotColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.2)
                  }

                  // Mini Controller Silhouette
                  Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 14
                    visible: slotPill.pad !== null

                    ControllerArt {
                      mini: true
                      layout: slotPill.pad ? slotPill.pad.layout : "generic"
                      modelLabel: slotPill.pad ? (slotPill.pad.modelLabel || slotPill.pad.name) : ""
                      maker: slotPill.pad ? slotPill.pad.maker : ""
                      playerColor: slotPill.slotColor
                      ledColor: (slotPill.pad && slotPill.pad.profile && slotPill.pad.profile.ledColor) ? slotPill.pad.profile.ledColor : slotPill.slotColor
                      buttons: slotPill.isSel ? root.liveButtons : (slotPill.pad ? slotPill.pad.buttons : ({}))
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (slotPill.pad ? Style.space(38) : Style.space(14))
                    spacing: 1

                    Text {
                      text: "P" + (slotPill.index + 1)
                      color: slotPill.isSel ? slotPill.slotColor : (slotPill.pad ? root.barForeground : Qt.darker(root.barForeground, 1.8))
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      width: parent.width
                      elide: Text.ElideRight
                      text: slotPill.pad ? (slotPill.pad.percent >= 0 ? slotPill.pad.percent + "%" : slotPill.pad.connection) : "empty"
                      color: slotPill.pad ? Qt.darker(root.barForeground, 1.3) : Qt.darker(root.barForeground, 2.0)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: 8
                    }
                  }
                }
              }
            }
          }

          // Segmented Tab Bar (Visible in top menu mode)
          Rectangle {
            visible: !root.isSideMenu
            width: parent.width
            height: Style.space(32)
            radius: Math.max(4, Style.cornerRadius)
            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
            border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
            border.width: 1

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              spacing: Style.space(2)

              Repeater {
                model: root.tabNames

                delegate: Rectangle {
                  id: tabItem
                  required property string modelData
                  required property int index

                  readonly property bool isCurrent: root.currentTab === index
                  width: (parent.width - (root.tabNames.length - 1) * Style.space(2)) / root.tabNames.length
                  height: parent.height
                  radius: Math.max(3, Style.cornerRadius - 1)
                  color: isCurrent
                    ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.18)
                    : tabItemMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                    : "transparent"
                  border.color: isCurrent ? root.playerColor : "transparent"
                  border.width: isCurrent ? 1 : 0

                  Behavior on color { ColorAnimation { duration: 70 } }

                  Text {
                    anchors.centerIn: parent
                    text: tabItem.modelData
                    color: tabItem.isCurrent ? root.playerColor : (tabItemMouse.containsMouse ? root.barForeground : Qt.darker(root.barForeground, 1.4))
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: tabItem.isCurrent
                  }

                  MouseArea {
                    id: tabItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.currentTab = tabItem.index
                      tabFlick.contentY = 0
                    }
                  }
                }
              }
            }
          }

          // Main Content Layout: Side Menu + Tab Content
          Row {
            width: parent.width
            spacing: Style.space(10)
            layoutDirection: root.menuPosition === "right" ? Qt.RightToLeft : Qt.LeftToRight

            // Side Navigation Column (Left / Right)
            Column {
              id: sideNavCol
              visible: root.isSideMenu
              width: visible ? Style.space(138) : 0
              spacing: Style.space(6)

              // Compact Slot Selector (2x2 grid)
              Grid {
                columns: 2
                spacing: Style.space(4)
                width: parent.width

                Repeater {
                  model: 4
                  delegate: Rectangle {
                    id: sideSlotPill
                    required property int index
                    readonly property var pad: root.pads && root.pads.length > index ? root.pads[index] : null
                    readonly property bool isSel: root.sel && pad && pad.id === root.sel.id
                    readonly property color slotColor: GamepadModel.playerColor(index + 1, Color)

                    width: (parent.width - Style.space(4)) / 2
                    height: Style.space(24)
                    radius: Math.max(3, Style.cornerRadius - 2)
                    color: isSel ? Qt.rgba(slotColor.r, slotColor.g, slotColor.b, 0.2) : "transparent"
                    border.color: isSel ? slotColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                    border.width: isSel ? 1.5 : 1

                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(3)
                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5; height: 5; radius: 2.5
                        color: sideSlotPill.pad ? sideSlotPill.slotColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.2)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "P" + (sideSlotPill.index + 1)
                        color: sideSlotPill.isSel ? sideSlotPill.slotColor : (sideSlotPill.pad ? root.barForeground : Qt.darker(root.barForeground, 1.8))
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: sideSlotPill.isSel
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: sideSlotPill.pad ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: if (sideSlotPill.pad) root.select(sideSlotPill.pad.id)
                    }
                  }
                }
              }

              // Vertical Navigation Tabs
              Column {
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: [
                    { name: "Overview", icon: "🎮" },
                    { name: "Sticks & Triggers", icon: "🎯" },
                    { name: "Haptics & Audio", icon: "🔊" },
                    { name: "Motion & Gyro", icon: "🧭" },
                    { name: "JoyLab", icon: "🕹️" },
                    { name: "Device Specs", icon: "📋" }
                  ]

                  delegate: Rectangle {
                    id: sideTabItem
                    required property var modelData
                    required property int index
                    readonly property bool isCur: root.currentTab === index

                    width: parent.width
                    height: Style.space(32)
                    radius: Math.max(3, Style.cornerRadius - 1)
                    color: isCur
                      ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.18)
                      : sideTabMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06) : "transparent"
                    border.color: isCur ? root.playerColor : "transparent"
                    border.width: isCur ? 1 : 0

                    Row {
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(6)

                      Text {
                        text: sideTabItem.modelData.icon
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        text: sideTabItem.modelData.name
                        color: sideTabItem.isCur ? root.playerColor : (sideTabMouse.containsMouse ? root.barForeground : Qt.darker(root.barForeground, 1.4))
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: sideTabItem.isCur
                        elide: Text.ElideRight
                        width: parent.width - Style.space(22)
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      id: sideTabMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.currentTab = sideTabItem.index
                        tabFlick.contentY = 0
                      }
                    }
                  }
                }
              }
            }

            // Tab Content View Area
            Item {
              id: tabContainer
              width: root.isSideMenu ? parent.width - Style.space(148) : parent.width
              height: Math.min(Style.space(500), tabFlickCol.implicitHeight)
              clip: true

            Flickable {
              id: tabFlick
              anchors.fill: parent
              contentWidth: width
              contentHeight: tabFlickCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Connections {
                target: root
                function onCurrentTabChanged() {
                  tabFlick.contentY = 0
                }
              }

              Column {
                id: tabFlickCol
                width: parent.width
                spacing: Style.space(8)

                // ---------------------------------------------------- TAB 0: OVERVIEW
                Column {
                  visible: root.currentTab === 0
                  width: parent.width
                  spacing: Style.space(8)

                  // Interactive Vector Controller Art (kenney-cap enhanced;
                  // the live deck stays vector so overlays always align)
                  ControllerArt {
                    id: overviewArt
                    anchors.horizontalCenter: parent.horizontalCenter
                    layout: root.sel ? root.sel.layout : "generic"
                    modelLabel: root.sel ? (root.sel.modelLabel || root.sel.name) : ""
                    maker: root.sel ? root.sel.maker : ""
                    playerColor: root.playerColor
                    ledColor: root.currentLedColor
                    touchpadState: root.touchpadState
                    buttons: root.liveButtons
                    axes: root.liveAxes
                    axisNames: root.sel && root.sel.axisNames ? root.sel.axisNames : []
                    profile: root.sel && root.sel.profile ? root.sel.profile : null
                    buttonPreset: (root.sel && (root.sel.buttonPreset || (root.sel.profile && root.sel.profile.buttonPreset))) ? (root.sel.buttonPreset || root.sel.profile.buttonPreset) : ""
                    gyro: root.liveGyro
                    remapMode: root.remapModeActive
                    rumbleActive: root.rumbleActive
                    rumbleWeak: root.rumbleWeak
                    rumbleStrong: root.rumbleStrong
                    width: Style.space(310)
                    height: Style.space(190)

                    onTouchpadInteracted: function(tx, ty, pressed) {
                      root.handleTouchpadInteraction(tx, ty, pressed)
                    }
                    onRequestRemap: function(role, index, label) {
                      remapModal.open(role, index, label)
                    }
                    onButtonClicked: function(index, pressed) {
                      root.handleVirtualButton(index, pressed)
                    }
                    onDpadClicked: function(dir, pressed) {
                      root.handleVirtualDpad(dir, pressed)
                    }
                    onStickMoved: function(side, sx, sy) {
                      root.handleVirtualStick(side, sx, sy, true)
                    }
                    onStickReleased: function(side) {
                      root.handleVirtualStick(side, 0, 0, false)
                    }
                    onTriggerMoved: function(side, val) {
                      root.handleVirtualTrigger(side, val)
                    }
                  }

                  // Dual Shoulder Trigger & Bumper Telemetry HUD
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - Style.space(16), Style.space(310))
                    height: Style.space(36)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)
                    border.width: 1

                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(10)

                      // Left Trigger (LT / L2 / ZL)
                      Row {
                        spacing: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                          width: Style.space(22); height: Style.space(18); radius: 3
                          color: (root.liveButtons && !!root.liveButtons[root.sel && root.sel.buttonTables ? root.sel.buttonTables.bumperL : 4]) ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                          border.color: (root.liveButtons && !!root.liveButtons[root.sel && root.sel.buttonTables ? root.sel.buttonTables.bumperL : 4]) ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.20)
                          border.width: 1
                          Text {
                            anchors.centerIn: parent
                            text: root.sel && root.sel.layout === "ps" ? "L1" : (root.sel && root.sel.layout === "switch" ? "L" : "LB")
                            color: (root.liveButtons && !!root.liveButtons[root.sel && root.sel.buttonTables ? root.sel.buttonTables.bumperL : 4]) ? "#FFFFFF" : root.barForeground
                            font.pixelSize: 8; font.bold: true
                          }
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 2
                          Row {
                            spacing: 4
                            Text {
                              text: root.sel && root.sel.layout === "ps" ? "L2" : (root.sel && root.sel.layout === "switch" ? "ZL" : "LT")
                              color: root.barForeground; font.pixelSize: 8; font.bold: true
                            }
                            Text {
                              text: Math.round(root.triggerNorm("l") * 100) + "%"
                              color: root.triggerNorm("l") > 0.03 ? root.playerColor : Qt.darker(root.barForeground, 1.4)
                              font.pixelSize: 8; font.bold: true
                            }
                          }
                          Rectangle {
                            width: Style.space(78); height: 5; radius: 2.5
                            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                            Rectangle {
                              height: parent.height; width: parent.width * Math.max(0, Math.min(1, root.triggerNorm("l")))
                              radius: 2.5; color: root.playerColor
                            }
                          }
                        }
                      }

                      // Divider
                      Rectangle {
                        width: 1; height: Style.space(20); anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                      }

                      // Right Trigger (RT / R2 / ZR)
                      Row {
                        spacing: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 2
                          Row {
                            spacing: 4
                            anchors.right: parent.right
                            Text {
                              text: Math.round(root.triggerNorm("r") * 100) + "%"
                              color: root.triggerNorm("r") > 0.03 ? root.playerColor : Qt.darker(root.barForeground, 1.4)
                              font.pixelSize: 8; font.bold: true
                            }
                            Text {
                              text: root.sel && root.sel.layout === "ps" ? "R2" : (root.sel && root.sel.layout === "switch" ? "ZR" : "RT")
                              color: root.barForeground; font.pixelSize: 8; font.bold: true
                            }
                          }
                          Rectangle {
                            width: Style.space(78); height: 5; radius: 2.5
                            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                            Rectangle {
                              height: parent.height; width: parent.width * Math.max(0, Math.min(1, root.triggerNorm("r")))
                              radius: 2.5; color: root.playerColor
                              anchors.right: parent.right
                            }
                          }
                        }

                        Rectangle {
                          width: Style.space(22); height: Style.space(18); radius: 3
                          color: (root.liveButtons && !!root.liveButtons[root.sel && root.sel.buttonTables ? root.sel.buttonTables.bumperR : 5]) ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                          border.color: (root.liveButtons && !!root.liveButtons[root.sel && root.sel.buttonTables ? root.sel.buttonTables.bumperR : 5]) ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.20)
                          border.width: 1
                          Text {
                            anchors.centerIn: parent
                            text: root.sel && root.sel.layout === "ps" ? "R1" : (root.sel && root.sel.layout === "switch" ? "R" : "RB")
                            color: (root.liveButtons && !!root.liveButtons[root.sel && root.sel.buttonTables ? root.sel.buttonTables.bumperR : 5]) ? "#FFFFFF" : root.barForeground
                            font.pixelSize: 8; font.bold: true
                          }
                        }
                      }
                    }
                  }

                  // Mode Selector: Test Mode vs Remap Mode
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - Style.space(16), Style.space(310))
                    height: Style.space(28)
                    radius: height / 2
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                    border.color: root.remapModeActive
                      ? root.playerColor
                      : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                    border.width: 1

                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      Rectangle {
                        width: (parent.parent.width - Style.space(12)) / 2
                        height: Style.space(22)
                        radius: height / 2
                        color: !root.remapModeActive
                          ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                          : "transparent"
                        border.color: !root.remapModeActive ? root.playerColor : "transparent"
                        border.width: 1

                        Text {
                          anchors.centerIn: parent
                          text: "🎮 Test Inputs"
                          color: !root.remapModeActive ? root.playerColor : Qt.darker(root.barForeground, 1.4)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: !root.remapModeActive
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.remapModeActive = false
                        }
                      }

                      Rectangle {
                        width: (parent.parent.width - Style.space(12)) / 2
                        height: Style.space(22)
                        radius: height / 2
                        color: root.remapModeActive
                          ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.30)
                          : "transparent"
                        border.color: root.remapModeActive ? root.playerColor : "transparent"
                        border.width: 1

                        Text {
                          anchors.centerIn: parent
                          text: "⚙️ Remap SVG Buttons"
                          color: root.remapModeActive ? root.playerColor : Qt.darker(root.barForeground, 1.4)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: root.remapModeActive
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.remapModeActive = true
                        }
                      }
                    }
                  }

                  // Matched gamepadla database entry card — photo shown fully
                  // (AspectFit) in its own frame so nothing is cut on the sides.
                  Rectangle {
                    visible: root.matched !== null
                    width: parent.width
                    height: Style.space(78)
                    radius: Math.max(4, Style.cornerRadius)
                    color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.07)
                    border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25)
                    border.width: 1
                    clip: true

                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(10)
                      spacing: Style.space(10)

                      // Photo frame, letterboxed (whole controller visible)
                      Rectangle {
                        width: Style.space(128)
                        height: parent.height
                        radius: Math.max(3, Style.cornerRadius - 1)
                        clip: true
                        color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.08)
                        border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                        border.width: 1

                        Image {
                          anchors.centerIn: parent
                          width: parent.width - Style.space(8)
                          height: parent.height - Style.space(8)
                          source: root.matchedImage
                          fillMode: Image.PreserveAspectFit
                          asynchronous: true
                          mipmap: true
                          smooth: true
                          visible: root.matchedImage !== ""
                        }
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Style.space(128) - Style.space(10)
                        spacing: Style.space(3)
                        clip: true

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: root.matchTitle
                          color: root.playerColor
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: root.matchVerdict
                          color: Qt.darker(root.barForeground, 1.4)
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: 9
                          textFormat: Text.PlainText
                        }

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: root.matchMetrics
                          color: Qt.darker(root.barForeground, 1.2)
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: 8
                          font.bold: true
                          textFormat: Text.PlainText
                        }
                      }
                    }
                  }

                  // Overview Status Chips (2 columns)
                  Grid {
                    columns: 2
                    width: parent.width
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(6)

                    Chip {
                      width: (parent.width - Style.space(8)) / 2
                      label: "Connection"
                      iconSource: root.sel ? Qt.resolvedUrl(GamepadModel.connectionIcon(root.sel.bus, root.sel.phys)) : ""
                      value: root.sel ? root.sel.connection : "—"
                      sub: root.sel ? ("/dev/input/" + root.sel.id) : ""
                      foreground: root.barForeground
                    }

                    Chip {
                      width: (parent.width - Style.space(8)) / 2
                      label: "Battery"
                      value: root.sel ? GamepadModel.batteryLabel(root.sel.percent, root.sel.charging) : "—"
                      sub: root.sel && root.sel.percent >= 0
                        ? (root.sel.percent <= root.lowBatteryThreshold ? "low — charge soon" : (root.sel.charging ? "charging" : "healthy"))
                        : "wired constant power"
                      valueColor: root.sel ? GamepadModel.batteryText(root.barForeground, Color, root.sel.percent, root.lowBatteryThreshold) : root.barForeground
                      foreground: root.barForeground
                    }

                    Chip {
                      width: (parent.width - Style.space(8)) / 2
                      label: "Polling Rate & Latency"
                      value: root.showLatency && root.sel
                        ? (root.sel.avgMs > 0 ? GamepadModel.latencyLabel(root.sel.avgMs, root.sel.eps) : root.stats.formattedHz + " · " + root.stats.avgMs.toFixed(1) + " ms")
                        : "hidden"
                      sub: root.sel && root.sel.jitter !== undefined
                        ? ("±" + root.sel.jitter.toFixed(2) + " ms jitter")
                        : (root.sel && root.sel.live ? "live stream" : "press a button")
                      foreground: root.barForeground
                    }

                    Chip {
                      width: (parent.width - Style.space(8)) / 2
                      label: "Mode / Protocol"
                      value: root.sel ? root.sel.protocol : "—"
                      sub: root.sel ? ((root.sel.maker ? root.sel.maker + " · " : "") + root.sel.driverNote) : ""
                      foreground: root.barForeground
                    }

                    Chip {
                      width: parent.width
                      label: "Hardware Layout"
                      value: root.sel ? (root.sel.axisCount + " axes · " + root.sel.buttonCount + " buttons" + (root.sel.motionNode ? " · 6-DOF gyro" : "")) : "—"
                      sub: root.sel ? GamepadModel.shapeLabel(root.sel.layout) : ""
                      foreground: root.barForeground
                    }
                  }
                }

                // ---------------------------------------------------- TAB 1: STICKS & TRIGGERS
                Column {
                  visible: root.currentTab === 1
                  width: parent.width
                  spacing: Style.space(8)

                  // Side-by-side Circularity Radars
                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    CircularityRadar {
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(245)
                      title: "Left Stick Radar"
                      rawX: root.stickX("l")
                      rawY: root.stickY("l")
                      deadzone: root.dzFor("l")
                      playerColor: root.playerColor
                    }

                    CircularityRadar {
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(245)
                      title: "Right Stick Radar"
                      rawX: root.stickX("r")
                      rawY: root.stickY("r")
                      deadzone: root.dzFor("r")
                      playerColor: root.playerColor
                    }
                  }

                  // Stick Deadzones (Inner & Outer)
                  PanelSectionHeader {
                    text: "Stick Deadzones & Boundaries"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "L Stick Inner DZ"
                    minValue: 0
                    maxValue: 0.50
                    value: root.dzFor("l")
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.setDz("stickL", v) }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "R Stick Inner DZ"
                    minValue: 0
                    maxValue: 0.50
                    value: root.dzFor("r")
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.setDz("stickR", v) }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "L Stick Outer DZ"
                    minValue: 0.50
                    maxValue: 1.00
                    value: root.sel && root.sel.profile && isFinite(Number(root.sel.profile.outerL)) ? Number(root.sel.profile.outerL) : 1.00
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.setProfileVal("outerL", v) }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "R Stick Outer DZ"
                    minValue: 0.50
                    maxValue: 1.00
                    value: root.sel && root.sel.profile && isFinite(Number(root.sel.profile.outerR)) ? Number(root.sel.profile.outerR) : 1.00
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.setProfileVal("outerR", v) }
                  }

                  // Response Curve Preset Picker
                  PanelSectionHeader {
                    text: "Response Curve Preset"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    readonly property var curves: ["Linear", "Dynamic", "Smooth", "Aggressive"]
                    readonly property string activeCurve: (root.sel && root.sel.profile && root.sel.profile.curve) ? String(root.sel.profile.curve).toLowerCase() : "linear"

                    Repeater {
                      model: parent.curves

                      delegate: Rectangle {
                        id: curveBtn
                        required property string modelData
                        required property int index

                        readonly property bool isSelected: parent.activeCurve === curveBtn.modelData.toLowerCase()
                        width: (parent.width - 3 * Style.space(6)) / 4
                        height: Style.space(28)
                        radius: Math.max(4, Style.cornerRadius)
                        color: isSelected
                          ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                          : curveMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                          : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                        border.color: isSelected ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                        border.width: isSelected ? 1.5 : 1

                        Text {
                          anchors.centerIn: parent
                          text: curveBtn.modelData
                          color: curveBtn.isSelected ? root.playerColor : root.barForeground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: curveBtn.isSelected
                        }

                        MouseArea {
                          id: curveMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.setProfileVal("curve", curveBtn.modelData.toLowerCase())
                        }
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    text: {
                      var c = (root.sel && root.sel.profile && root.sel.profile.curve) ? String(root.sel.profile.curve).toLowerCase() : "linear"
                      if (c === "dynamic") return "Dynamic: Exponential cubic blend with high precision center and rapid outer velocity."
                      if (c === "smooth") return "Smooth: Sinusoidal S-curve providing cinematic transitions and gentle centering."
                      if (c === "aggressive") return "Aggressive: Immediate high-response curve for fast twitch aiming and steering."
                      return "Linear: 1:1 proportional response curve without algorithmic modification."
                    }
                    color: Qt.darker(root.barForeground, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  // Triggers & Analog Travel
                  PanelSectionHeader {
                    text: "Triggers & Analog Travel"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  // Analog Trigger Meters
                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Rectangle {
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(26)
                      radius: Math.max(4, Style.cornerRadius)
                      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                      border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Rectangle {
                        height: parent.height
                        width: Math.max(0, Math.min(1, root.triggerNorm("l"))) * parent.width
                        radius: Math.max(4, Style.cornerRadius)
                        color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.3)
                      }

                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.sel && root.sel.layout === "ps" ? "L2" : "LT") + " Travel"
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.triggerNorm("l") * 100) + "%"
                        color: root.playerColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    Rectangle {
                      width: (parent.width - Style.space(8)) / 2
                      height: Style.space(26)
                      radius: Math.max(4, Style.cornerRadius)
                      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                      border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Rectangle {
                        height: parent.height
                        width: Math.max(0, Math.min(1, root.triggerNorm("r"))) * parent.width
                        radius: Math.max(4, Style.cornerRadius)
                        color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.3)
                      }

                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.sel && root.sel.layout === "ps" ? "R2" : "RT") + " Travel"
                        color: root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.triggerNorm("r") * 100) + "%"
                        color: root.playerColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "L Trigger DZ"
                    minValue: 0
                    maxValue: 0.50
                    value: root.sel && root.sel.profile ? root.sel.profile.trigL : 0.05
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.setDz("trigL", v) }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "R Trigger DZ"
                    minValue: 0
                    maxValue: 0.50
                    value: root.sel && root.sel.profile ? root.sel.profile.trigR : 0.05
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.setDz("trigR", v) }
                  }

                  // Button Remapping & Controller GUI
                  PanelSectionHeader {
                    text: "Button Remapping & Input Inspector"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  // Layout Preset Selection
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    readonly property string activeRemap: (root.sel && root.sel.profile && root.sel.profile.remapPreset) ? root.sel.profile.remapPreset : "standard"

                    Rectangle {
                      width: (parent.width - Style.space(6)) * 0.48
                      height: Style.space(28)
                      radius: Math.max(4, Style.cornerRadius)
                      color: parent.activeRemap === "standard"
                        ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                        : stdMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                        : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                      border.color: parent.activeRemap === "standard" ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: parent.activeRemap === "standard" ? 1.5 : 1

                      Text {
                        anchors.centerIn: parent
                        text: "Standard (A·B·X·Y)"
                        color: parent.parent.activeRemap === "standard" ? root.playerColor : root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: parent.parent.activeRemap === "standard"
                      }

                      MouseArea {
                        id: stdMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setProfileVal("remapPreset", "standard")
                      }
                    }

                    Rectangle {
                      width: (parent.width - Style.space(6)) * 0.52
                      height: Style.space(28)
                      radius: Math.max(4, Style.cornerRadius)
                      color: parent.activeRemap === "nintendo_swap"
                        ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                        : swapMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                        : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                      border.color: parent.activeRemap === "nintendo_swap" ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: parent.activeRemap === "nintendo_swap" ? 1.5 : 1

                      Text {
                        anchors.centerIn: parent
                        text: "Nintendo Swap (B·A·Y·X)"
                        color: parent.parent.activeRemap === "nintendo_swap" ? root.playerColor : root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: parent.parent.activeRemap === "nintendo_swap"
                      }

                      MouseArea {
                        id: swapMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setProfileVal("remapPreset", "nintendo_swap")
                      }
                    }
                  }

                  // Stick Inversion Toggles
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    readonly property bool invL: !!(root.sel && root.sel.profile && root.sel.profile.invertLY)
                    readonly property bool invR: !!(root.sel && root.sel.profile && root.sel.profile.invertRY)

                    Rectangle {
                      width: (parent.width - Style.space(6)) / 2
                      height: Style.space(26)
                      radius: Math.max(4, Style.cornerRadius)
                      color: parent.invL
                        ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.20)
                        : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                      border.color: parent.invL ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Text {
                        anchors.centerIn: parent
                        text: (parent.parent.invL ? "✓ " : "") + "Invert Left Stick Y"
                        color: parent.parent.invL ? root.playerColor : root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: parent.parent.invL
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setProfileVal("invertLY", !parent.parent.invL)
                      }
                    }

                    Rectangle {
                      width: (parent.width - Style.space(6)) / 2
                      height: Style.space(26)
                      radius: Math.max(4, Style.cornerRadius)
                      color: parent.invR
                        ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.20)
                        : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                      border.color: parent.invR ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Text {
                        anchors.centerIn: parent
                        text: (parent.parent.invR ? "✓ " : "") + "Invert Right Stick Y"
                        color: parent.parent.invR ? root.playerColor : root.barForeground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: parent.parent.invR
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setProfileVal("invertRY", !parent.parent.invR)
                      }
                    }
                  }

                  // Live Button Remapper & Input Inspector Grid
                  Rectangle {
                    width: parent.width
                    height: remapCol.implicitHeight + Style.space(16)
                    radius: Math.max(4, Style.cornerRadius)
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.03)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)
                    border.width: 1
                    clip: true

                    Column {
                      id: remapCol
                      width: parent.width - Style.space(16)
                      x: Style.space(8)
                      y: Style.space(8)
                      spacing: Style.space(6)

                      // Header Row with Title and Reset Button
                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - resetRemapBtn.width - Style.space(8)
                          text: "Button Remapper & SVG Badges (Click to Remap)"
                          color: Qt.darker(root.barForeground, 1.4)
                          font.family: Style.font.family
                          font.pixelSize: 8
                          font.bold: true
                          elide: Text.ElideRight
                        }

                        Rectangle {
                          id: resetRemapBtn
                          width: resetTxt.implicitWidth + Style.space(12)
                          height: Style.space(18)
                          radius: height / 2
                          color: resetMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.20) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                          border.color: resetMouse.containsMouse ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                          border.width: 1
                          visible: !!(root.sel && root.sel.profile && ((root.sel.profile.buttonMap && Object.keys(root.sel.profile.buttonMap).length > 0) || root.sel.profile.remapPreset === "nintendo_swap"))

                          Text {
                            id: resetTxt
                            anchors.centerIn: parent
                            text: "↺ Reset Remaps"
                            color: resetMouse.containsMouse ? root.playerColor : root.barForeground
                            font.family: Style.font.family
                            font.pixelSize: 7
                            font.bold: true
                          }

                          MouseArea {
                            id: resetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetAllRemaps()
                          }
                        }
                      }

                      // Row 1: Action Face Buttons
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? (root.sel.buttonPreset || root.sel.layout) : "generic", root.sel ? (root.sel.profile || root.sel.buttonPreset) : null)

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "faceBottom"
                          role: "South / Bottom"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "faceBottom", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "faceBottom", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.faceBottom
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceBottom]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "faceRight"
                          role: "East / Right"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "faceRight", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "faceRight", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.faceRight
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceRight]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "faceLeft"
                          role: "West / Left"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "faceLeft", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "faceLeft", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.faceLeft
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceLeft]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "faceTop"
                          role: "North / Top"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "faceTop", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "faceTop", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.faceTop
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceTop]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }
                      }

                      // Row 2: Shoulders and Triggers
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? (root.sel.buttonPreset || root.sel.layout) : "generic", root.sel ? (root.sel.profile || root.sel.buttonPreset) : null)

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "bumperL"
                          role: "Left Shoulder"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "bumperL", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "bumperL", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.bumperL
                          active: root.liveButtons && !!root.liveButtons[parent.t.bumperL]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "bumperR"
                          role: "Right Shoulder"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "bumperR", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "bumperR", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.bumperR
                          active: root.liveButtons && !!root.liveButtons[parent.t.bumperR]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "triggerL"
                          role: "Left Trigger"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "triggerL", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "triggerL", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.triggerL
                          axisHint: "Axis LT"
                          active: root.triggerNorm("l") > 0.15 || (root.liveButtons && !!root.liveButtons[parent.t.triggerL])
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "triggerR"
                          role: "Right Trigger"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "triggerR", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "triggerR", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.triggerR
                          axisHint: "Axis RT"
                          active: root.triggerNorm("r") > 0.15 || (root.liveButtons && !!root.liveButtons[parent.t.triggerR])
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }
                      }

                      // Row 3: D-Pad Directions (supports digital buttons and Hat0X/Hat0Y axes)
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? (root.sel.buttonPreset || root.sel.layout) : "generic", root.sel ? (root.sel.profile || root.sel.buttonPreset) : null)

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "dpadUp"
                          role: "D-Pad Up"
                          label: "▲"
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "dpadUp", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.dpadUp
                          axisHint: "Hat0Y -"
                          active: GamepadModel.isDpadActive("up", root.liveButtons, root.liveAxes, parent.t, root.axisMap)
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "dpadDown"
                          role: "D-Pad Down"
                          label: "▼"
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "dpadDown", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.dpadDown
                          axisHint: "Hat0Y +"
                          active: GamepadModel.isDpadActive("down", root.liveButtons, root.liveAxes, parent.t, root.axisMap)
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "dpadLeft"
                          role: "D-Pad Left"
                          label: "◀"
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "dpadLeft", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.dpadLeft
                          axisHint: "Hat0X -"
                          active: GamepadModel.isDpadActive("left", root.liveButtons, root.liveAxes, parent.t, root.axisMap)
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "dpadRight"
                          role: "D-Pad Right"
                          label: "▶"
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "dpadRight", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.dpadRight
                          axisHint: "Hat0X +"
                          active: GamepadModel.isDpadActive("right", root.liveButtons, root.liveAxes, parent.t, root.axisMap)
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }
                      }

                      // Row 4: Stick Clicks and Back/Start Center Buttons
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? (root.sel.buttonPreset || root.sel.layout) : "generic", root.sel ? (root.sel.profile || root.sel.buttonPreset) : null)

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "stickL"
                          role: "Left Stick Click"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "stickL", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "stickL", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.stickL
                          active: root.liveButtons && !!root.liveButtons[parent.t.stickL]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "stickR"
                          role: "Right Stick Click"
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "stickR", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "stickR", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.stickR
                          active: root.liveButtons && !!root.liveButtons[parent.t.stickR]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "centerLeft"
                          role: root.sel && root.sel.layout === "switch" ? "Minus (-)" : (root.sel && root.sel.layout === "playstation" ? "Share / Create" : "Back / View")
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "centerLeft", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "centerLeft", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.centerLeft
                          active: root.liveButtons && !!root.liveButtons[parent.t.centerLeft]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          roleKey: "centerRight"
                          role: root.sel && root.sel.layout === "switch" ? "Plus (+)" : (root.sel && root.sel.layout === "playstation" ? "Options" : "Start / Menu")
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "centerRight", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "centerRight", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.centerRight
                          active: root.liveButtons && !!root.liveButtons[parent.t.centerRight]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }
                      }

                      // Row 5: System Center Buttons (Guide / Home and Share / Capture / Touchpad)
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? (root.sel.buttonPreset || root.sel.layout) : "generic", root.sel ? (root.sel.profile || root.sel.buttonPreset) : null)

                        RemapPill {
                          width: (parent.width - Style.space(6)) / 2
                          roleKey: "centerTop"
                          role: root.sel && root.sel.layout === "switch" ? "Home Button" : (root.sel && root.sel.layout === "playstation" ? "PS Button" : "Guide Button")
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "centerTop", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "centerTop", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.centerTop
                          active: root.liveButtons && !!root.liveButtons[parent.t.centerTop]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }

                        RemapPill {
                          width: (parent.width - Style.space(6)) / 2
                          roleKey: "centerExtra"
                          role: root.sel && root.sel.layout === "switch" ? "Capture Button" : (root.sel && root.sel.layout === "playstation" ? "Touchpad Click" : "Share Button")
                          label: GamepadModel.buttonLabel(root.sel ? root.sel.layout : "xbox", "centerExtra", root.sel ? root.sel.profile : null)
                          svgSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", "centerExtra", root.sel ? root.sel.profile : null))
                          btnIdx: parent.t.centerExtra
                          active: root.liveButtons && !!root.liveButtons[parent.t.centerExtra]
                          accent: root.playerColor
                          foreground: root.barForeground
                          onClicked: remapModal.open(roleKey, btnIdx, label)
                        }
                      }
                    }
                  }

                  // -------------------------------------------------- Capacitive Touchpad Diagnostic Bench
                  PanelSectionHeader {
                    text: "Capacitive Touchpad / Trackpad Diagnostic Bench"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(260)
                    radius: Math.max(6, Style.cornerRadius)
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.03)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                    border.width: 1

                    Column {
                      anchors.fill: parent
                      anchors.margins: Style.space(10)
                      spacing: Style.space(8)

                      // Header / Status Line
                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          text: (root.sel && root.sel.touchpadNode)
                            ? ("Companion Node: " + root.sel.touchpadNode)
                            : ((root.sel && root.sel.hasTouchpad) ? "Capacitive Touchpad Active" : "Interactive Trackpad Simulator")
                          color: (root.sel && root.sel.hasTouchpad) ? root.playerColor : Qt.darker(root.barForeground, 1.3)
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.bold: true
                          font.pixelSize: Style.font.caption
                        }

                        Item { width: 1; height: 1 }

                        Rectangle {
                          width: Style.space(110)
                          height: Style.space(20)
                          radius: 10
                          color: root.touchpadState.active ? Qt.rgba(0, 0.9, 1.0, 0.20) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                          border.color: root.touchpadState.active ? "#00e5ff" : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                          border.width: 1

                          Text {
                            anchors.centerIn: parent
                            text: root.touchpadState.active ? "TOUCH DETECTED" : "IDLE / READY"
                            color: root.touchpadState.active ? "#00e5ff" : Qt.darker(root.barForeground, 1.4)
                            font.bold: true
                            font.pixelSize: Style.font.caption - 1
                          }
                        }
                      }

                      // Interactive Touchpad Canvas Surface
                      Rectangle {
                        id: trackpadCanvas
                        width: parent.width
                        height: Style.space(145)
                        radius: Math.max(6, Style.cornerRadius)
                        color: Qt.rgba(0, 0, 0, 0.45)
                        border.color: root.touchpadState.active ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.5) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                        border.width: root.touchpadState.active ? 1.5 : 1
                        clip: true

                        // Subtle grid lines
                        Rectangle {
                          x: parent.width * 0.5; y: 0
                          width: 1; height: parent.height
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.07)
                        }
                        Rectangle {
                          x: 0; y: parent.height * 0.5
                          width: parent.width; height: 1
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.07)
                        }

                        // Bottom 20% Physical Click Divider
                        Rectangle {
                          x: 0; y: parent.height * 0.80
                          width: parent.width; height: 1
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                        }
                        Rectangle {
                          x: parent.width * 0.5; y: parent.height * 0.80
                          width: 1; height: parent.height * 0.20
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.20)
                        }

                        // Click zone labels
                        Text {
                          x: parent.width * 0.25 - width / 2; y: parent.height * 0.88 - height / 2
                          text: "LEFT CLICK ZONE"
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.25)
                          font.pixelSize: Style.font.caption - 2
                          font.bold: true
                        }
                        Text {
                          x: parent.width * 0.75 - width / 2; y: parent.height * 0.88 - height / 2
                          text: "RIGHT CLICK ZONE"
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.25)
                          font.pixelSize: Style.font.caption - 2
                          font.bold: true
                        }

                        // Motion drag trails
                        Repeater {
                          model: root.touchpadState.trails || []
                          delegate: Rectangle {
                            required property var modelData
                            required property int index
                            x: modelData.x * trackpadCanvas.width - width / 2
                            y: modelData.y * trackpadCanvas.height - height / 2
                            width: 6; height: 6; radius: 3
                            color: "#00e5ff"
                            opacity: Math.max(0.15, 0.85 * ((index + 1) / Math.max(1, (root.touchpadState.trails ? root.touchpadState.trails.length : 1))))
                          }
                        }

                        // Active finger contact indicators
                        Repeater {
                          model: root.touchpadState.fingers || []
                          delegate: Item {
                            required property var modelData
                            required property int index
                            x: modelData.x * trackpadCanvas.width
                            y: modelData.y * trackpadCanvas.height

                            // Outer pulse aura
                            Rectangle {
                              anchors.centerIn: parent
                              width: 32; height: 32; radius: 16
                              color: "transparent"
                              border.color: index === 0 ? "#00e5ff" : "#ff007f"
                              border.width: 1.5
                              opacity: 0.5
                            }

                            // Inner contact point
                            Rectangle {
                              anchors.centerIn: parent
                              width: 14; height: 14; radius: 7
                              color: index === 0 ? "#00e5ff" : "#ff007f"
                              border.color: "#ffffff"
                              border.width: 2
                            }

                            // Coordinate label tag
                            Rectangle {
                              anchors.left: parent.right
                              anchors.leftMargin: 6
                              anchors.verticalCenter: parent.verticalCenter
                              width: Style.space(90); height: Style.space(18); radius: 3
                              color: Qt.rgba(0, 0, 0, 0.75)
                              border.color: index === 0 ? "#00e5ff" : "#ff007f"
                              border.width: 1

                              Text {
                                anchors.centerIn: parent
                                text: "F" + (index + 1) + ": " + Math.round(modelData.x * 1920) + ", " + Math.round(modelData.y * 1080)
                                color: "#ffffff"
                                font.pixelSize: Style.font.caption - 2
                                font.bold: true
                              }
                            }
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.CrossCursor
                          onPressed: function(mouse) {
                            root.handleTouchpadInteraction(mouse.x / width, mouse.y / height, true)
                          }
                          onPositionChanged: function(mouse) {
                            if (pressed) {
                              root.handleTouchpadInteraction(mouse.x / width, mouse.y / height, true)
                            }
                          }
                          onReleased: function(mouse) {
                            root.handleTouchpadInteraction(mouse.x / width, mouse.y / height, false)
                          }
                          onCanceled: {
                            root.handleTouchpadInteraction(0.5, 0.5, false)
                          }
                        }
                      }

                      // Quick Gesture Simulation Pills & Coordinate HUD
                      Row {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          width: (parent.width - 4 * Style.space(6)) / 5
                          text: "Tap"
                          fontSize: Style.font.caption
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: root.simulateGesture("tap")
                        }

                        Button {
                          width: (parent.width - 4 * Style.space(6)) / 5
                          text: "2-Finger"
                          fontSize: Style.font.caption
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: root.simulateGesture("twofinger")
                        }

                        Button {
                          width: (parent.width - 4 * Style.space(6)) / 5
                          text: "Pinch"
                          fontSize: Style.font.caption
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: root.simulateGesture("pinch")
                        }

                        Button {
                          width: (parent.width - 4 * Style.space(6)) / 5
                          text: "Swipe"
                          fontSize: Style.font.caption
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: root.simulateGesture("swipe")
                        }

                        Button {
                          width: (parent.width - 4 * Style.space(6)) / 5
                          text: "Clear"
                          fontSize: Style.font.caption
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: root.simulateGesture("clear")
                        }
                      }

                      // Bottom HUD Status Readout
                      Row {
                        width: parent.width
                        spacing: Style.space(12)

                        Text {
                          text: "ZONE: " + root.touchpadState.zone
                          color: root.barForeground
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }

                        Text {
                          text: "CONTACT: " + (root.touchpadState.fingers && root.touchpadState.fingers.length > 0 ? (root.touchpadState.fingers.length + " Finger(s)") : "None")
                          color: root.touchpadState.active ? "#00e5ff" : Qt.darker(root.barForeground, 1.4)
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          text: "PRESSURE: " + Math.round(root.touchpadState.pressure * 100) + "%"
                          color: Qt.darker(root.barForeground, 1.3)
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }
                }

                // ---------------------------------------------------- TAB 2: HAPTICS STUDIO
                Column {
                  visible: root.currentTab === 2
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSectionHeader {
                    text: "Dual-Motor Rumble Mixer"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  ControllerArt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    layout: root.sel ? root.sel.layout : "generic"
                    modelLabel: root.sel ? (root.sel.modelLabel || root.sel.name) : ""
                    maker: root.sel ? root.sel.maker : ""
                    playerColor: root.playerColor
                    ledColor: root.currentLedColor
                    touchpadState: root.touchpadState
                    buttons: root.liveButtons
                    axes: root.liveAxes
                    axisNames: root.sel && root.sel.axisNames ? root.sel.axisNames : []
                    profile: root.sel && root.sel.profile ? root.sel.profile : null
                    buttonPreset: (root.sel && (root.sel.buttonPreset || (root.sel.profile && root.sel.profile.buttonPreset))) ? (root.sel.buttonPreset || root.sel.profile.buttonPreset) : ""
                    rumbleActive: root.rumbleActive
                    rumbleWeak: root.rumbleActive ? root.rumbleWeak : root.hfMixer
                    rumbleStrong: root.rumbleActive ? root.rumbleStrong : root.lfMixer
                    width: Style.space(280)
                    height: Style.space(165)
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Low Freq (LF)"
                    minValue: 0
                    maxValue: 1.00
                    value: root.lfMixer
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.lfMixer = v }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "High Freq (HF)"
                    minValue: 0
                    maxValue: 1.00
                    value: root.hfMixer
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) { root.hfMixer = v }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Master Power"
                    minValue: 0.10
                    maxValue: 1.00
                    value: root.sel && root.sel.profile && isFinite(Number(root.sel.profile.rumble)) ? Number(root.sel.profile.rumble) : 1.00
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) {
                      if (root.svc && root.sel) root.svc.setRumble(root.sel.id, Math.round(v * 100) / 100)
                    }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Rumble Duration (" + (root.rumbleDurationMs / 1000).toFixed(1) + "s)"
                    minValue: 0.20
                    maxValue: 3.00
                    value: root.rumbleDurationMs / 1000.0
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) {
                      root.rumbleDurationMs = Math.round(v * 10) * 100
                    }
                  }

                  // Quick duration preset pills
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: [
                        { label: "0.5s", ms: 500 },
                        { label: "1.2s", ms: 1200 },
                        { label: "2.0s", ms: 2000 },
                        { label: "3.0s", ms: 3000 }
                      ]
                      delegate: Rectangle {
                        id: durPill
                        required property var modelData
                        readonly property bool isSelected: root.rumbleDurationMs === modelData.ms
                        width: (parent.width - 3 * Style.space(6)) / 4
                        height: Style.space(26)
                        radius: Math.max(3, Style.cornerRadius)
                        color: isSelected ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22) : (durMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04))
                        border.color: isSelected ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                        border.width: isSelected ? 1.5 : 1

                        Text {
                          anchors.centerIn: parent
                          text: durPill.modelData.label
                          color: durPill.isSelected ? root.playerColor : root.barForeground
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.bold: durPill.isSelected
                          font.pixelSize: Style.font.caption
                        }

                        MouseArea {
                          id: durMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.rumbleDurationMs = durPill.modelData.ms
                        }
                      }
                    }
                  }

                  Button {
                    width: parent.width
                    text: "▶ Test Rumble Mix (" + (root.rumbleDurationMs / 1000).toFixed(1) + "s)"
                    focusable: true
                    foreground: root.barForeground
                    accent: root.playerColor
                    onClicked: root.triggerRumble(root.hfMixer, root.lfMixer, root.rumbleDurationMs)
                  }

                  // Rhythm Test Patterns
                  PanelSectionHeader {
                    text: "Vibration Rhythm Test Patterns"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                      width: (parent.width - 3 * Style.space(6)) / 4
                      text: "Pulse"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playRhythm("pulse")
                    }

                    Button {
                      width: (parent.width - 3 * Style.space(6)) / 4
                      text: "Heartbeat"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playRhythm("heartbeat")
                    }

                    Button {
                      width: (parent.width - 3 * Style.space(6)) / 4
                      text: "Ramp"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playRhythm("ramp")
                    }

                    Button {
                      width: (parent.width - 3 * Style.space(6)) / 4
                      text: "Heavy Burst"
                      fontSize: Style.font.caption
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playRhythm("burst")
                    }
                  }

                  // -------------------------------------------------- HD Rumble Melodic Player
                  PanelSectionHeader {
                    text: "Nintendo HD Rumble Melodic MIDI Player"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Text {
                    width: parent.width
                    text: "Plays acoustic musical tones through controller Linear Resonant Actuators (LRAs) by driving force feedback pulses at pitch frequencies."
                    color: Qt.darker(root.barForeground, 1.4)
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Column {
                    width: parent.width
                    spacing: Style.space(4)

                    // Track selector row 1
                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      Repeater {
                        model: [
                          { id: "mario", name: "🍄 Mario Ground Theme" },
                          { id: "zelda", name: "⚔️ Zelda Overworld" }
                        ]
                        delegate: Rectangle {
                          id: mBtn1
                          required property var modelData
                          readonly property bool isSel: root.selectedMidiTrack === modelData.id
                          width: (parent.width - Style.space(6)) / 2
                          height: Style.space(30)
                          radius: Math.max(4, Style.cornerRadius)
                          color: isSel ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25) : (mMouse1.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04))
                          border.color: isSel ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                          border.width: isSel ? 1.5 : 1

                          Text {
                            anchors.centerIn: parent
                            text: mBtn1.modelData.name
                            color: mBtn1.isSel ? root.playerColor : root.barForeground
                            font.bold: mBtn1.isSel
                            font.pixelSize: Style.font.caption
                          }
                          MouseArea {
                            id: mMouse1
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMidiTrack = mBtn1.modelData.id
                          }
                        }
                      }
                    }

                    // Track selector row 2
                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      Repeater {
                        model: [
                          { id: "tetris", name: "🧱 Tetris Type A" },
                          { id: "pokemon", name: "⚡ Pokémon Battle" }
                        ]
                        delegate: Rectangle {
                          id: mBtn2
                          required property var modelData
                          readonly property bool isSel: root.selectedMidiTrack === modelData.id
                          width: (parent.width - Style.space(6)) / 2
                          height: Style.space(30)
                          radius: Math.max(4, Style.cornerRadius)
                          color: isSel ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25) : (mMouse2.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04))
                          border.color: isSel ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                          border.width: isSel ? 1.5 : 1

                          Text {
                            anchors.centerIn: parent
                            text: mBtn2.modelData.name
                            color: mBtn2.isSel ? root.playerColor : root.barForeground
                            font.bold: mBtn2.isSel
                            font.pixelSize: Style.font.caption
                          }
                          MouseArea {
                            id: mMouse2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMidiTrack = mBtn2.modelData.id
                          }
                        }
                      }
                    }

                    // Track selector row 3: Quick jingles
                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      Repeater {
                        model: [
                          { id: "coin", name: "🪙 Coin Pickup" },
                          { id: "oneup", name: "🍄 1-Up Fanfare" },
                          { id: "sine", name: "〰️ Sine Sweep" }
                        ]
                        delegate: Rectangle {
                          id: mBtn3
                          required property var modelData
                          readonly property bool isSel: root.selectedMidiTrack === modelData.id
                          width: (parent.width - 2 * Style.space(6)) / 3
                          height: Style.space(28)
                          radius: Math.max(4, Style.cornerRadius)
                          color: isSel ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25) : (mMouse3.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04))
                          border.color: isSel ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                          border.width: isSel ? 1.5 : 1

                          Text {
                            anchors.centerIn: parent
                            text: mBtn3.modelData.name
                            color: mBtn3.isSel ? root.playerColor : root.barForeground
                            font.bold: mBtn3.isSel
                            font.pixelSize: Style.font.caption
                          }
                          MouseArea {
                            id: mMouse3
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMidiTrack = mBtn3.modelData.id
                          }
                        }
                      }
                    }
                  }

                  // Melodic Player Play/Stop Bar
                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      width: (parent.width - Style.space(8)) * 0.70
                      text: (root.svc && root.svc.isMelodyPlaying) ? "⏹ Stop Playing Melody" : ("▶ Play " + root.selectedMidiTrack.toUpperCase() + " Haptic Track")
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: {
                        if (root.svc && root.svc.isMelodyPlaying) root.stopMelody()
                        else root.playMelody(root.selectedMidiTrack, root.midiVolume)
                      }
                    }

                    Rectangle {
                      width: (parent.width - Style.space(8)) * 0.30
                      height: Style.space(32)
                      radius: Math.max(4, Style.cornerRadius)
                      color: (root.svc && root.svc.isMelodyPlaying) ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                      border.color: (root.svc && root.svc.isMelodyPlaying) ? root.playerColor : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: (root.svc && root.svc.isMelodyPlaying) ? "♫ VIBRATING..." : "READY"
                        color: (root.svc && root.svc.isMelodyPlaying) ? root.playerColor : Qt.darker(root.barForeground, 1.4)
                        font.bold: true
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  // -------------------------------------------------- Speaker & 3.5mm Audio Jack Diagnostic Bench
                  PanelSectionHeader {
                    text: "Speaker & 3.5mm Audio Jack Diagnostic"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  // Audio sink status card
                  Rectangle {
                    width: parent.width
                    height: Style.space(42)
                    radius: Math.max(4, Style.cornerRadius)
                    color: Qt.rgba(0.06, 0.09, 0.16, 0.65)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                    border.width: 1

                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(8)
                      spacing: Style.space(10)

                      Text {
                        text: "🎧"
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                          text: (root.svc && root.svc.audioInfo && root.svc.audioInfo.activeLabel) ? root.svc.audioInfo.activeLabel : "Host Audio Jack / Headphones"
                          color: root.barForeground
                          font.bold: true
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          text: (root.svc && root.svc.audioInfo && root.svc.audioInfo.hasControllerSink)
                            ? "Controller Onboard DAC Active · 48 kHz Stereo"
                            : "Host Audio Output · Smart Fallback for Nintendo Switch Pro"
                          color: Qt.darker(root.barForeground, 1.4)
                          font.pixelSize: 10
                        }
                      }
                    }
                  }

                  // Audio Channel Test Buttons
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                      width: (parent.width - 2 * Style.space(6)) / 3
                      text: "◀ Left Tone"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playAudioTone("left", "")
                    }

                    Button {
                      width: (parent.width - 2 * Style.space(6)) / 3
                      text: "Right Tone ▶"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playAudioTone("right", "")
                    }

                    Button {
                      width: (parent.width - 2 * Style.space(6)) / 3
                      text: "▶ Stereo Ping"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: root.playAudioTone("stereo", "")
                    }
                  }

                  // DualSense Adaptive Trigger Tuning
                  PanelSectionHeader {
                    text: "DualSense Adaptive Trigger Studio"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  // Trigger mode selector (clean 2-row grid with legible font)
                  Column {
                    width: parent.width
                    spacing: Style.space(4)

                    Row {
                      width: parent.width
                      spacing: Style.space(4)
                      readonly property var rowModes: ["Off", "Rigid", "Pulse"]

                      Repeater {
                        model: parent.rowModes
                        delegate: Rectangle {
                          id: tmBtn1
                          required property string modelData
                          readonly property bool isSelected: root.selectedTriggerMode === tmBtn1.modelData
                          width: (parent.width - 2 * Style.space(4)) / 3
                          height: Style.space(28)
                          radius: Math.max(4, Style.cornerRadius)
                          color: isSelected
                            ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                            : tmMouse1.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                            : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                          border.color: isSelected ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                          border.width: isSelected ? 1.5 : 1

                          Text {
                            anchors.centerIn: parent
                            text: tmBtn1.modelData
                            color: tmBtn1.isSelected ? root.playerColor : root.barForeground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: tmBtn1.isSelected
                          }

                          MouseArea {
                            id: tmMouse1
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              root.selectedTriggerMode = tmBtn1.modelData
                              root.applyTriggerEffect(root.triggerStartPos, root.triggerForce)
                            }
                          }
                        }
                      }
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(4)
                      readonly property var rowModes2: ["Bow", "Machine Gun"]

                      Repeater {
                        model: parent.rowModes2
                        delegate: Rectangle {
                          id: tmBtn2
                          required property string modelData
                          readonly property bool isSelected: root.selectedTriggerMode === tmBtn2.modelData
                          width: (parent.width - Style.space(4)) / 2
                          height: Style.space(28)
                          radius: Math.max(4, Style.cornerRadius)
                          color: isSelected
                            ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                            : tmMouse2.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                            : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                          border.color: isSelected ? root.playerColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                          border.width: isSelected ? 1.5 : 1

                          Text {
                            anchors.centerIn: parent
                            text: tmBtn2.modelData
                            color: tmBtn2.isSelected ? root.playerColor : root.barForeground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: tmBtn2.isSelected
                          }

                          MouseArea {
                            id: tmMouse2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              root.selectedTriggerMode = tmBtn2.modelData
                              root.applyTriggerEffect(root.triggerStartPos, root.triggerForce)
                            }
                          }
                        }
                      }
                    }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Trigger Start Pos"
                    minValue: 0
                    maxValue: 1.00
                    value: root.triggerStartPos
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) {
                      root.triggerStartPos = v
                      root.applyTriggerEffect(v, root.triggerForce)
                    }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Trigger Force"
                    minValue: 0
                    maxValue: 1.00
                    value: root.triggerForce
                    foreground: root.barForeground
                    accent: root.playerColor
                    onMoved: function (v) {
                      root.triggerForce = v
                      root.applyTriggerEffect(root.triggerStartPos, v)
                    }
                  }

                  Text {
                    width: parent.width
                    text: "DualSense adaptive triggers transmit native hidraw force packets. Supported on PS5 DualSense pads over USB/Bluetooth and the simulator bench."
                    color: Qt.darker(root.barForeground, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  // -------------------------------------------------- PS4 & PS5 RGB Lightbar Studio
                  PanelSectionHeader {
                    text: "PlayStation 4 & 5 RGB Lightbar Studio"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Text {
                    width: parent.width
                    text: (root.sel && root.sel.hasRgbLed)
                      ? "Direct sysfs & hidraw hardware lightbar control for connected DualSense / DualShock 4. Changes synchronize live with the on-screen deck."
                      : "Lightbar studio and color simulator. Select presets or calibrate custom RGB lighting curves."
                    color: Qt.darker(root.barForeground, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  // Glowing Lightbar Preview
                  Rectangle {
                    width: parent.width
                    height: Style.space(48)
                    radius: Math.max(6, Style.cornerRadius)
                    color: Qt.rgba(0, 0, 0, 0.40)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                    border.width: 1

                    // Diffuse outer glow
                    Rectangle {
                      anchors.centerIn: parent
                      width: parent.width * 0.78
                      height: Style.space(22)
                      radius: height / 2
                      color: root.currentLedColor
                      opacity: 0.35
                    }

                    // Intense core light tube
                    Rectangle {
                      anchors.centerIn: parent
                      width: parent.width * 0.72
                      height: Style.space(10)
                      radius: height / 2
                      color: root.currentLedColor
                      border.color: Qt.rgba(1, 1, 1, 0.85)
                      border.width: 1.5
                    }

                    // Hex code pill badge
                    Rectangle {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(85)
                      height: Style.space(22)
                      radius: 4
                      color: Qt.rgba(0, 0, 0, 0.6)
                      border.color: root.currentLedColor
                      border.width: 1

                      Text {
                        anchors.centerIn: parent
                        text: String(root.currentLedColor).toUpperCase()
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.bold: true
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  // Preset Palette Chips (Row 1)
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: GamepadModel.PS_LED_PRESETS.slice(0, 4)
                      delegate: Rectangle {
                        id: psChip1
                        required property var modelData
                        readonly property bool isSelected: root.currentLedColor.toString().toLowerCase() === modelData.hex.toLowerCase()
                        width: (parent.width - 3 * Style.space(6)) / 4
                        height: Style.space(30)
                        radius: Math.max(4, Style.cornerRadius)
                        color: isSelected ? Qt.rgba(modelData.r / 255.0, modelData.g / 255.0, modelData.b / 255.0, 0.25) : (chipMouse1.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04))
                        border.color: isSelected ? modelData.hex : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                        border.width: isSelected ? 1.5 : 1

                        Row {
                          anchors.centerIn: parent
                          spacing: Style.space(4)

                          Rectangle {
                            width: 8; height: 8; radius: 4
                            color: psChip1.modelData.hex
                            border.color: "#ffffff"
                            border.width: 0.5
                          }

                          Text {
                            text: psChip1.modelData.name
                            color: psChip1.isSelected ? root.barForeground : Qt.darker(root.barForeground, 1.2)
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: psChip1.isSelected
                          }
                        }

                        MouseArea {
                          id: chipMouse1
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.applyLedColor(psChip1.modelData.r, psChip1.modelData.g, psChip1.modelData.b)
                        }
                      }
                    }
                  }

                  // Preset Palette Chips (Row 2)
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: GamepadModel.PS_LED_PRESETS.slice(4, 8)
                      delegate: Rectangle {
                        id: psChip2
                        required property var modelData
                        readonly property bool isSelected: root.currentLedColor.toString().toLowerCase() === modelData.hex.toLowerCase()
                        width: (parent.width - 3 * Style.space(6)) / 4
                        height: Style.space(30)
                        radius: Math.max(4, Style.cornerRadius)
                        color: isSelected ? Qt.rgba(modelData.r / 255.0, modelData.g / 255.0, modelData.b / 255.0, 0.25) : (chipMouse2.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04))
                        border.color: isSelected ? modelData.hex : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                        border.width: isSelected ? 1.5 : 1

                        Row {
                          anchors.centerIn: parent
                          spacing: Style.space(4)

                          Rectangle {
                            width: 8; height: 8; radius: 4
                            color: psChip2.modelData.hex
                            border.color: "#ffffff"
                            border.width: 0.5
                          }

                          Text {
                            text: psChip2.modelData.name
                            color: psChip2.isSelected ? root.barForeground : Qt.darker(root.barForeground, 1.2)
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: psChip2.isSelected
                          }
                        }

                        MouseArea {
                          id: chipMouse2
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.applyLedColor(psChip2.modelData.r, psChip2.modelData.g, psChip2.modelData.b)
                        }
                      }
                    }
                  }

                  // Channel Sliders (Red, Green, Blue)
                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Red Channel (" + root.ledR + " / 255)"
                    minValue: 0
                    maxValue: 255
                    value: root.ledR
                    foreground: root.barForeground
                    accent: "#ff3b30"
                    onMoved: function (v) {
                      root.applyLedColor(Math.round(v), root.ledG, root.ledB)
                    }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Green Channel (" + root.ledG + " / 255)"
                    minValue: 0
                    maxValue: 255
                    value: root.ledG
                    foreground: root.barForeground
                    accent: "#34c759"
                    onMoved: function (v) {
                      root.applyLedColor(root.ledR, Math.round(v), root.ledB)
                    }
                  }

                  DeadzoneSlider {
                    width: parent.width
                    labelText: "Blue Channel (" + root.ledB + " / 255)"
                    minValue: 0
                    maxValue: 255
                    value: root.ledB
                    foreground: root.barForeground
                    accent: "#007aff"
                    onMoved: function (v) {
                      root.applyLedColor(root.ledR, root.ledG, Math.round(v))
                    }
                  }
                }

                // ---------------------------------------------------- TAB 3: MOTION & GYRO
                Column {
                  visible: root.currentTab === 3
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSectionHeader {
                    text: "6-DOF Artificial Horizon & Orientation"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  // 3D Motion Orientation Viewport
                  Rectangle {
                    width: parent.width
                    height: Style.space(220)
                    radius: Math.max(4, Style.cornerRadius)
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                    border.width: 1
                    clip: true

                    ControllerArt {
                      anchors.centerIn: parent
                      width: Math.min(parent.width - Style.space(24), Style.space(320))
                      height: Style.space(195)
                      layout: root.sel ? root.sel.layout : "generic"
                      modelLabel: root.sel ? (root.sel.modelLabel || root.sel.name) : ""
                      maker: root.sel ? root.sel.maker : ""
                      playerColor: root.playerColor
                      ledColor: root.currentLedColor
                      touchpadState: root.touchpadState
                      buttons: root.liveButtons
                      axes: root.liveAxes
                      axisNames: root.sel && root.sel.axisNames ? root.sel.axisNames : []
                      profile: root.sel && root.sel.profile ? root.sel.profile : null
                      buttonPreset: (root.sel && (root.sel.buttonPreset || (root.sel.profile && root.sel.profile.buttonPreset))) ? (root.sel.buttonPreset || root.sel.profile.buttonPreset) : ""
                      gyro: root.liveGyro
                      rumbleActive: root.rumbleActive
                      rumbleWeak: root.rumbleWeak
                      rumbleStrong: root.rumbleStrong
                      interactive: true
                      onButtonClicked: function(index, pressed) {
                        root.handleVirtualButton(index, pressed)
                      }
                      onDpadClicked: function(dir, pressed) {
                        root.handleVirtualDpad(dir, pressed)
                      }
                      onStickMoved: function(side, sx, sy) {
                        root.handleVirtualStick(side, sx, sy, true)
                      }
                      onStickReleased: function(side) {
                        root.handleVirtualStick(side, 0, 0, false)
                      }
                      onTriggerMoved: function(side, val) {
                        root.handleVirtualTrigger(side, val)
                      }
                    }

                    // Live Orientation Degrees Badge
                    Rectangle {
                      anchors.top: parent.top
                      anchors.left: parent.left
                      anchors.margins: Style.space(8)
                      height: Style.space(20)
                      radius: height / 2
                      color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.16)
                      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.35)
                      border.width: 1
                      width: orientRow.implicitWidth + Style.space(12)

                      Row {
                        id: orientRow
                        anchors.centerIn: parent
                        spacing: Style.space(6)
                        Text {
                          text: "PITCH " + (root.liveGyro && isFinite(root.liveGyro.pitch) ? ((root.liveGyro.pitch >= 0 ? "+" : "") + root.liveGyro.pitch.toFixed(1) + "°") : "0.0°")
                          color: root.playerColor
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                        Text {
                          text: "·"
                          color: root.playerColor
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          text: "ROLL " + (root.liveGyro && isFinite(root.liveGyro.roll) ? ((root.liveGyro.roll >= 0 ? "+" : "") + root.liveGyro.roll.toFixed(1) + "°") : "0.0°")
                          color: root.playerColor
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                        Text {
                          text: "·"
                          color: root.playerColor
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          text: "YAW " + (root.liveGyro && isFinite(root.liveGyro.yaw) ? ((root.liveGyro.yaw >= 0 ? "+" : "") + root.liveGyro.yaw.toFixed(1) + "°") : "0.0°")
                          color: root.playerColor
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                    }
                  }

                  // Artificial Horizon Gauge
                  ArtificialHorizon {
                    width: parent.width
                    height: Style.space(170)
                    gyro: root.liveGyro
                    bias: root.sel && root.sel.profile && root.sel.profile.gyroBias ? root.sel.profile.gyroBias : null
                    accent: root.playerColor
                    foreground: root.barForeground
                  }

                  PanelSectionHeader {
                    text: "Accelerometer & Gyroscope Telemetry"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  // Telemetry Meters
                  Column {
                    width: parent.width
                    spacing: Style.space(4)

                    BiBar {
                      label: "Ax"
                      val: root.liveGyro ? (root.liveGyro.ax || 0) : 0
                      maxAbs: 19.6
                      unit: "m/s²"
                      accent: root.playerColor
                      foreground: root.barForeground
                    }

                    BiBar {
                      label: "Ay"
                      val: root.liveGyro ? (root.liveGyro.ay || 0) : 0
                      maxAbs: 19.6
                      unit: "m/s²"
                      accent: root.playerColor
                      foreground: root.barForeground
                    }

                    BiBar {
                      label: "Az"
                      val: root.liveGyro ? (root.liveGyro.az || 0) : 9.81
                      maxAbs: 19.6
                      unit: "m/s²"
                      accent: root.playerColor
                      foreground: root.barForeground
                    }

                    BiBar {
                      label: "Gx"
                      val: root.liveGyro ? ((root.liveGyro.gx || 0) - (root.sel && root.sel.profile && root.sel.profile.gyroBias ? root.sel.profile.gyroBias.x : 0)) : 0
                      maxAbs: 100.0
                      unit: "°/s"
                      accent: root.playerColor
                      foreground: root.barForeground
                    }

                    BiBar {
                      label: "Gy"
                      val: root.liveGyro ? ((root.liveGyro.gy || 0) - (root.sel && root.sel.profile && root.sel.profile.gyroBias ? root.sel.profile.gyroBias.y : 0)) : 0
                      maxAbs: 100.0
                      unit: "°/s"
                      accent: root.playerColor
                      foreground: root.barForeground
                    }

                    BiBar {
                      label: "Gz"
                      val: root.liveGyro ? ((root.liveGyro.gz || 0) - (root.sel && root.sel.profile && root.sel.profile.gyroBias ? root.sel.profile.gyroBias.z : 0)) : 0
                      maxAbs: 100.0
                      unit: "°/s"
                      accent: root.playerColor
                      foreground: root.barForeground
                    }
                  }

                  // Gyroscope Zero-Drift Calibration Studio
                  Rectangle {
                    width: parent.width
                    height: calCol.implicitHeight + Style.space(24)
                    radius: Math.max(6, Style.cornerRadius)
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                    border.color: (root.sel && root.sel.calibratingGyro)
                      ? root.playerColor
                      : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                    border.width: 1

                    Column {
                      id: calCol
                      anchors.fill: parent
                      anchors.margins: Style.space(12)
                      spacing: Style.space(10)

                      // Header Row
                      Item {
                        width: parent.width
                        height: Style.space(24)

                        Text {
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: "🎯 Gyroscope Recalibration & Zero-Drift Nulling"
                          color: root.barForeground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.subtitle
                          font.bold: true
                        }

                        // Status Badge
                        Rectangle {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          height: Style.space(22)
                          radius: height / 2
                          color: (root.sel && root.sel.calibratingGyro)
                            ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22)
                            : (root.sel && root.sel.profile && root.sel.profile.gyroBias && (root.sel.profile.gyroBias.x !== 0 || root.sel.profile.gyroBias.y !== 0 || root.sel.profile.gyroBias.z !== 0))
                              ? Qt.rgba(0.13, 0.77, 0.37, 0.18)
                              : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
                          border.color: (root.sel && root.sel.calibratingGyro)
                            ? root.playerColor
                            : (root.sel && root.sel.profile && root.sel.profile.gyroBias && (root.sel.profile.gyroBias.x !== 0 || root.sel.profile.gyroBias.y !== 0 || root.sel.profile.gyroBias.z !== 0))
                              ? "#22c55e"
                              : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.2)
                          border.width: 1
                          width: calBadgeRow.implicitWidth + Style.space(14)

                          Row {
                            id: calBadgeRow
                            anchors.centerIn: parent
                            spacing: Style.space(6)
                            Rectangle {
                              anchors.verticalCenter: parent.verticalCenter
                              width: 6; height: 6; radius: 3
                              color: (root.sel && root.sel.calibratingGyro)
                                ? root.playerColor
                                : (root.sel && root.sel.profile && root.sel.profile.gyroBias && (root.sel.profile.gyroBias.x !== 0 || root.sel.profile.gyroBias.y !== 0 || root.sel.profile.gyroBias.z !== 0))
                                  ? "#22c55e"
                                  : Qt.darker(root.barForeground, 1.6)
                            }
                            Text {
                              anchors.verticalCenter: parent.verticalCenter
                              text: (root.sel && root.sel.calibratingGyro)
                                ? ("Sampling (" + (root.sel.gyroCalCount || 0) + "/20)…")
                                : (root.sel && root.sel.profile && root.sel.profile.gyroBias && (root.sel.profile.gyroBias.x !== 0 || root.sel.profile.gyroBias.y !== 0 || root.sel.profile.gyroBias.z !== 0))
                                  ? "Calibrated & Active"
                                  : "Factory Zero"
                              color: (root.sel && root.sel.calibratingGyro)
                                ? root.playerColor
                                : (root.sel && root.sel.profile && root.sel.profile.gyroBias && (root.sel.profile.gyroBias.x !== 0 || root.sel.profile.gyroBias.y !== 0 || root.sel.profile.gyroBias.z !== 0))
                                  ? "#22c55e"
                                  : Qt.darker(root.barForeground, 1.4)
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }
                        }
                      }

                      // Instruction and stored bias readout
                      Row {
                        width: parent.width
                        spacing: Style.space(12)

                        // 3 Bias Pills
                        Rectangle {
                          height: Style.space(28)
                          radius: 4
                          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                          border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                          width: biasPillRow.implicitWidth + Style.space(16)

                          Row {
                            id: biasPillRow
                            anchors.centerIn: parent
                            spacing: Style.space(10)
                            Text {
                              text: "Bias X: " + (root.sel && root.sel.profile && root.sel.profile.gyroBias ? (root.sel.profile.gyroBias.x >= 0 ? "+" : "") + root.sel.profile.gyroBias.x.toFixed(2) + "°/s" : "0.00°/s")
                              color: root.playerColor
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                            Text { text: "·"; color: Qt.darker(root.barForeground, 1.6); font.pixelSize: Style.font.caption }
                            Text {
                              text: "Bias Y: " + (root.sel && root.sel.profile && root.sel.profile.gyroBias ? (root.sel.profile.gyroBias.y >= 0 ? "+" : "") + root.sel.profile.gyroBias.y.toFixed(2) + "°/s" : "0.00°/s")
                              color: root.playerColor
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                            Text { text: "·"; color: Qt.darker(root.barForeground, 1.6); font.pixelSize: Style.font.caption }
                            Text {
                              text: "Bias Z: " + (root.sel && root.sel.profile && root.sel.profile.gyroBias ? (root.sel.profile.gyroBias.z >= 0 ? "+" : "") + root.sel.profile.gyroBias.z.toFixed(2) + "°/s" : "0.00°/s")
                              color: root.playerColor
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - biasPillRow.implicitWidth - Style.space(28)
                          text: "Offsets are subtracted from gyroscope telemetry to eliminate angular drift."
                          color: Qt.darker(root.barForeground, 1.4)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          wrapMode: Text.WordWrap
                          elide: Text.ElideRight
                        }
                      }

                      // Progress bar during calibration
                      Rectangle {
                        visible: !!(root.sel && root.sel.calibratingGyro)
                        width: parent.width
                        height: Style.space(4)
                        radius: 2
                        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.1)
                        clip: true

                        Rectangle {
                          anchors.left: parent.left
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          width: parent.width * Math.max(0.05, Math.min(1.0, (root.sel && root.sel.gyroCalProgress) ? root.sel.gyroCalProgress : 0))
                          color: root.playerColor
                          radius: 2
                        }
                      }

                      // Action Buttons
                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Button {
                          width: Style.space(220)
                          text: (root.sel && root.sel.calibratingGyro) ? "⏳ Calibrating Gyro…" : "🎯 Recalibrate Gyro Sensor"
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: {
                            if (root.svc && root.sel) {
                              root.svc.calibrateGyro(root.sel.id)
                            }
                          }
                        }

                        Button {
                          width: Style.space(130)
                          text: "↺ Reset Bias"
                          focusable: true
                          foreground: root.barForeground
                          accent: root.playerColor
                          onClicked: {
                            if (root.svc && root.sel) {
                              root.svc.resetGyroCalibration(root.sel.id)
                            }
                          }
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Keep pad flat & still on desk during calibration"
                          color: Qt.darker(root.barForeground, 1.5)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }
                }

                // ---------------------------------------------------- TAB 4: JOYLAB BENCHMARK GAME
                Column {
                  visible: root.currentTab === 4
                  width: parent.width
                  spacing: Style.space(8)

                  PanelSectionHeader {
                    text: "JoyLab: Chrome Dino Infinite Runner Benchmark"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Text {
                    width: parent.width
                    text: "Authentic Chrome T-Rex infinite scrolling runner benchmark. Jump over cacti, duck under flying pterodactyls, and test input latency, analog trigger actuation, and gyro steering under real-time 60 FPS conditions."
                    color: Qt.darker(root.barForeground, 1.4)
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  JoyLabGame {
                    id: joyLabInstance
                    width: parent.width
                    height: Style.space(380)
                    liveButtons: root.liveButtons
                    liveAxes: root.liveAxes
                    liveGyro: root.liveGyro
                    gyroBias: root.sel && root.sel.profile && root.sel.profile.gyroBias ? root.sel.profile.gyroBias : null
                    axisMap: root.axisMap
                    layout: root.sel ? root.sel.layout : "generic"
                    playerColor: root.playerColor
                    foregroundColor: root.barForeground
                    onRequestRumble: function(w, s, ms) {
                      root.triggerRumble(w, s, ms)
                    }
                    onRunCompleted: function(telemetry) {
                      root.latestJoyLabStats = telemetry
                      if (root.svc) root.svc.actionResult("JoyLab Dino Run Complete: " + telemetry.score + " pts · " + (telemetry.latencyMs || 0).toFixed(1) + "ms latency")
                    }
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      width: (parent.width - Style.space(8)) / 2
                      text: "↺ Restart Dino Runner"
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: joyLabInstance.resetGame()
                    }

                    Button {
                      width: (parent.width - Style.space(8)) / 2
                      text: "📊 View Performance Scorecard →"
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: {
                        root.currentTab = 5
                        tabFlick.contentY = 0
                      }
                    }
                  }
                }

                // ---------------------------------------------------- TAB 5: DEVICE SPECS & SCORECARD
                Column {
                  visible: root.currentTab === 5
                  width: parent.width
                  spacing: Style.space(6)

                  // Multi-Sector Performance Scorecard Card
                  PanelSectionHeader {
                    text: "Multi-Sector Performance Scorecard"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(165)
                    radius: Math.max(6, Style.cornerRadius)
                    color: Qt.rgba(0.06, 0.09, 0.16, 0.70)
                    border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.40)
                    border.width: 1

                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(10)
                      spacing: Style.space(12)

                      // Left badge: Big Grade Letter
                      Rectangle {
                        width: Style.space(110)
                        height: parent.height
                        radius: Math.max(6, Style.cornerRadius)
                        color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.18)
                        border.color: root.playerColor
                        border.width: 2

                        Column {
                          anchors.centerIn: parent
                          spacing: Style.space(2)

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.scorecard.overallGrade
                            color: root.scorecard.overallScore >= 88 ? "#22c55e" : (root.scorecard.overallScore >= 75 ? "#38bdf8" : "#f59e0b")
                            font.bold: true
                            font.pixelSize: 42
                          }

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.scorecard.overallScore + " / 100"
                            color: root.barForeground
                            font.bold: true
                            font.pixelSize: Style.font.caption
                          }

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "GRADE TIER"
                            color: Qt.darker(root.barForeground, 1.5)
                            font.pixelSize: 9
                          }
                        }
                      }

                      // Right side: 6 sector status rows
                      Column {
                        width: parent.width - Style.space(126)
                        height: parent.height
                        spacing: Style.space(4)

                        Repeater {
                          model: [
                            { name: "Stick Precision", sec: root.scorecard.sectors.sticks },
                            { name: "Polling & Latency", sec: root.scorecard.sectors.latency },
                            { name: "Buttons & Switches", sec: root.scorecard.sectors.buttons },
                            { name: "Haptics & HD Rumble", sec: root.scorecard.sectors.haptics },
                            { name: "6-DOF IMU Motion", sec: root.scorecard.sectors.motion },
                            { name: "Connectivity & Bus", sec: root.scorecard.sectors.connectivity }
                          ]

                          delegate: Row {
                            id: secRow
                            required property var modelData
                            width: parent.width
                            spacing: Style.space(6)

                            Rectangle {
                              width: Style.space(20)
                              height: Style.space(16)
                              radius: 3
                              color: secRow.modelData.sec.tier === "S" ? "#22c55e" : (secRow.modelData.sec.tier === "A" ? "#38bdf8" : (secRow.modelData.sec.tier === "B" ? "#eab308" : "#94a3b8"))
                              Text {
                                anchors.centerIn: parent
                                text: secRow.modelData.sec.tier
                                color: "#0f172a"
                                font.bold: true
                                font.pixelSize: 9
                              }
                            }

                            Text {
                              width: Style.space(110)
                              anchors.verticalCenter: parent.verticalCenter
                              text: secRow.modelData.name
                              color: root.barForeground
                              font.bold: true
                              font.pixelSize: Style.font.caption
                            }

                            Text {
                              anchors.verticalCenter: parent.verticalCenter
                              text: secRow.modelData.sec.label
                              color: Qt.darker(root.barForeground, 1.3)
                              font.pixelSize: Style.font.caption
                              elide: Text.ElideRight
                            }
                          }
                        }
                      }
                    }
                  }

                  // Copy Diagnostic Report Button
                  Button {
                    width: parent.width
                    text: "📋 Copy Markdown Diagnostic Report to Clipboard"
                    foreground: root.barForeground
                    accent: root.playerColor
                    onClicked: root.copyReportToClipboard()
                  }

                  PanelSectionHeader {
                    text: "Hardware Diagnostic Specification Sheet"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  SpecRow {
                    label: "Device Identifier"
                    value: root.sel ? root.sel.name : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Hardware Catalog"
                    value: root.matched
                      ? (root.matched.entry.n + (root.matched.entry.b ? " · " + root.matched.entry.b : "") + " (" + Math.round(root.matched.score * 100) + "% match)")
                      : "no catalog entry — generic rendering"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Verified Benchmark"
                    value: root.matched ? GamepadlaCatalog.benchmarkLabel(root.matched.entry) : "not benchmarked"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Best Link Latency"
                    value: (root.matched && GamepadlaCatalog.bestLatency(root.matched.entry))
                      ? GamepadlaCatalog.bestLatency(root.matched.entry).mode + ": " + GamepadlaCatalog.bestLatency(root.matched.entry).ms.toFixed(2) + " ms"
                      : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Interfaces & Platforms"
                    value: root.matched
                      ? (root.matched.entry.ifc && root.matched.entry.ifc.length ? root.matched.entry.ifc.join(", ") : "—") + " · " + (root.matched.entry.plats && root.matched.entry.plats.length ? root.matched.entry.plats.join(", ") : "—")
                      : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Retail Price"
                    value: root.matched && root.matched.entry.pr ? root.matched.entry.pr : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Vendor & Product ID"
                    value: root.sel ? (root.sel.vendor + ":" + root.sel.product + (root.sel.maker ? " (" + root.sel.maker + ")" : "")) : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Connection & Bus Type"
                    iconSource: root.sel ? Qt.resolvedUrl(GamepadModel.connectionIcon(root.sel.bus, root.sel.phys)) : ""
                    value: root.sel ? ("Bus " + root.sel.bus + " · " + root.sel.connection) : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Kernel Driver"
                    value: root.sel ? (root.sel.driver + " (" + root.sel.driverNote + ")") : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Input Subsystem Nodes"
                    value: root.sel ? ("/dev/input/" + root.sel.id + " · " + (root.sel.event ? "/dev/input/" + root.sel.event : "none")) : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Motion IMU Node"
                    value: root.sel && root.sel.motionNode ? ("/dev/input/" + root.sel.motionNode) : "None detected"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Hardware Layout"
                    value: root.sel ? (root.sel.buttonCount + " buttons · " + root.sel.axisCount + " axes (" + GamepadModel.shapeLabel(root.sel.layout) + ")") : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Polling Rate & Latency"
                    value: root.sel
                      ? ((root.sel.pollingRate || root.stats.hz) + " Hz · Avg: " + (root.sel.avgMs > 0 ? root.sel.avgMs.toFixed(2) : root.stats.avgMs.toFixed(2)) + " ms (Min: " + (root.sel.minMs > 0 ? root.sel.minMs.toFixed(2) : (root.stats.minMs > 0 ? root.stats.minMs.toFixed(2) : "0.00")) + " ms, Max: " + (root.sel.maxMs > 0 ? root.sel.maxMs.toFixed(2) : (root.stats.maxMs > 0 ? root.stats.maxMs.toFixed(2) : "0.00")) + " ms · ±" + (root.sel.jitter !== undefined ? root.sel.jitter.toFixed(2) : root.stats.jitter.toFixed(2)) + " ms jitter)")
                      : "—"
                    foreground: root.barForeground
                  }

                  SpecRow {
                    label: "Power & Battery Health"
                    value: root.sel
                      ? (root.sel.percent >= 0 ? (root.sel.percent + "% · " + (root.sel.charging ? "Charging ⚡" : "Discharging") + " · " + (root.sel.percent >= 20 ? "Healthy" : "Low")) : "Wired External Power")
                      : "—"
                    foreground: root.barForeground
                  }

                  // Hardware Certification Badges
                  PanelSectionHeader {
                    text: "Sensor Technology Badges"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Rectangle {
                      width: (parent.width - 2 * Style.space(8)) / 3
                      height: Style.space(38)
                      radius: Math.max(4, Style.cornerRadius)
                      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                      border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Row {
                        anchors.centerIn: parent
                        spacing: Style.space(6)

                        Image {
                          anchors.verticalCenter: parent.verticalCenter
                          source: Qt.resolvedUrl("assets/badge_polling.svg")
                          width: 22; height: 22
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 1
                          Text {
                            text: "Pro Polling"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            color: root.barForeground
                          }
                          Text {
                            text: (root.stats.hz >= 500 ? root.stats.hz + " Hz" : "High Speed")
                            font.family: Style.font.family
                            font.pixelSize: 8
                            color: Qt.darker(root.barForeground, 1.4)
                          }
                        }
                      }
                    }

                    Rectangle {
                      width: (parent.width - 2 * Style.space(8)) / 3
                      height: Style.space(38)
                      radius: Math.max(4, Style.cornerRadius)
                      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                      border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Row {
                        anchors.centerIn: parent
                        spacing: Style.space(6)

                        Image {
                          anchors.verticalCenter: parent.verticalCenter
                          source: Qt.resolvedUrl("assets/badge_hall.svg")
                          width: 22; height: 22
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 1
                          Text {
                            text: "Hall Effect"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            color: root.barForeground
                          }
                          Text {
                            text: "Magnetic"
                            font.family: Style.font.family
                            font.pixelSize: 8
                            color: Qt.darker(root.barForeground, 1.4)
                          }
                        }
                      }
                    }

                    Rectangle {
                      width: (parent.width - 2 * Style.space(8)) / 3
                      height: Style.space(38)
                      radius: Math.max(4, Style.cornerRadius)
                      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                      border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                      border.width: 1

                      Row {
                        anchors.centerIn: parent
                        spacing: Style.space(6)

                        Image {
                          anchors.verticalCenter: parent.verticalCenter
                          source: Qt.resolvedUrl("assets/badge_tmr.svg")
                          width: 22; height: 22
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 1
                          Text {
                            text: "TMR Sensors"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            color: root.barForeground
                          }
                          Text {
                            text: "Precision"
                            font.family: Style.font.family
                            font.pixelSize: 8
                            color: Qt.darker(root.barForeground, 1.4)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Scroll indicator
            Rectangle {
              id: scrollIndicator
              anchors.right: parent.right
              anchors.rightMargin: Style.space(2)
              y: tabFlick.visibleArea.yPosition * parent.height
              width: Style.space(3)
              height: Math.max(Style.space(20), tabFlick.visibleArea.heightRatio * parent.height)
              radius: width / 2
              color: root.playerColor
              visible: tabFlick.visibleArea.heightRatio < 1.0
              opacity: (tabFlick.moving || tabFlick.flicking) ? 0.9 : 0.35
              Behavior on opacity { NumberAnimation { duration: 150 } }
            }
          }
        }
      }

      // ---------------------------------------------------- Footer
        PanelSeparator { foreground: root.barForeground }

        Text {
          width: parent.width
          text: root.actionMsg !== ""
            ? root.actionMsg
            : (root.svc && root.svc.jstestAvailable
               ? "Scan " + (root.svc.scanIntervalMs / 1000) + "s · Live input active (" + (root.stats ? root.stats.formattedHz : "idle") + ")"
               : "Scan " + (root.svc ? root.svc.scanIntervalMs / 1000 : 2) + "s · Waiting for input")
          color: Qt.darker(root.barForeground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // ---------------------------------------------------- Button Remap Modal Overlay
      Rectangle {
        id: remapModal
        visible: false
        z: 200
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)

        property string targetRole: ""
        property int currentBtnIdx: -1
        property string currentLabel: ""

        function open(role, btnIdx, label) {
          targetRole = role
          currentBtnIdx = btnIdx
          currentLabel = label
          visible = true
        }

        function close() {
          visible = false
        }

        // Dismiss when clicking outside modal box
        MouseArea {
          anchors.fill: parent
          onClicked: remapModal.close()
        }

        // Modal Dialog Box
        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(420))
          height: Math.min(parent.height - Style.space(32), remapDialogCol.implicitHeight + Style.space(28))
          radius: Style.cornerRadius + 2
          color: Color.popups.background
          border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.45)
          border.width: 1.5
          clip: true

          MouseArea {
            anchors.fill: parent
            // Absorb clicks inside dialog
          }

          Column {
            id: remapDialogCol
            width: parent.width - Style.space(24)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(14)
            spacing: Style.space(8)

            // Header Row
            Row {
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(28)
                height: Style.space(28)
                radius: width / 2
                color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.20)
                border.color: root.playerColor
                border.width: 1

                Image {
                  anchors.centerIn: parent
                  width: 18; height: 18
                  source: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", remapModal.targetRole, root.sel ? root.sel.profile : null))
                  fillMode: Image.PreserveAspectFit
                  mipmap: true
                  visible: status === Image.Ready
                  layer.enabled: visible
                  layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.playerColor
                  }
                }
              }

              Column {
                width: parent.width - Style.space(68)
                spacing: 1

                Text {
                  text: "Remap " + remapModal.currentLabel
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  text: "Target Role: " + remapModal.targetRole + (remapModal.currentBtnIdx >= 0 ? (" (Physical Btn " + remapModal.currentBtnIdx + ")") : "")
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: 8
                }
              }

              // Close button
              Rectangle {
                width: Style.space(24)
                height: Style.space(24)
                radius: width / 2
                color: closeMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "✕"
                  color: root.barForeground
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: closeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: remapModal.close()
                }
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)
            }

            Text {
              text: "Choose a physical button or action to trigger this control:"
              color: Qt.darker(root.barForeground, 1.3)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            // Action Selection Grid
            Grid {
              width: parent.width
              columns: 2
              spacing: Style.space(6)

              readonly property var actions: [
                { role: "faceBottom", label: root.sel && root.sel.layout === "ps" ? "×" : "A", name: "A / Cross", idx: 0 },
                { role: "faceRight", label: root.sel && root.sel.layout === "ps" ? "○" : "B", name: "B / Circle", idx: 1 },
                { role: "faceLeft", label: root.sel && root.sel.layout === "ps" ? "□" : "X", name: "X / Square", idx: 2 },
                { role: "faceTop", label: root.sel && root.sel.layout === "ps" ? "△" : "Y", name: "Y / Triangle", idx: 3 },
                { role: "bumperL", label: root.sel && root.sel.layout === "ps" ? "L1" : "LB", name: "Left Bumper", idx: root.sel && root.sel.layout === "ps" ? 10 : 4 },
                { role: "bumperR", label: root.sel && root.sel.layout === "ps" ? "R1" : "RB", name: "Right Bumper", idx: root.sel && root.sel.layout === "ps" ? 11 : 5 },
                { role: "stickL", label: root.sel && root.sel.layout === "ps" ? "L3" : "LS", name: "L3 / Left Stick", idx: root.sel && root.sel.layout === "ps" ? 8 : 9 },
                { role: "stickR", label: root.sel && root.sel.layout === "ps" ? "R3" : "RS", name: "R3 / Right Stick", idx: root.sel && root.sel.layout === "ps" ? 9 : 10 },
                { role: "dpadUp", label: "▲", name: "D-Pad Up", idx: 11 },
                { role: "dpadDown", label: "▼", name: "D-Pad Down", idx: 12 },
                { role: "dpadLeft", label: "◀", name: "D-Pad Left", idx: 13 },
                { role: "dpadRight", label: "▶", name: "D-Pad Right", idx: 14 },
                { role: "centerLeft", label: root.sel && root.sel.layout === "ps" ? "Create" : "View", name: "Back / View", idx: root.sel && root.sel.layout === "ps" ? 4 : 6 },
                { role: "centerRight", label: root.sel && root.sel.layout === "ps" ? "Options" : "Menu", name: "Start / Menu", idx: root.sel && root.sel.layout === "ps" ? 5 : 7 }
              ]

              Repeater {
                model: parent.actions

                Rectangle {
                  id: optCard
                  width: (remapDialogCol.width - Style.space(6)) / 2
                  height: Style.space(34)
                  radius: Math.max(3, Style.cornerRadius - 1)
                  readonly property bool isCur: remapModal.currentBtnIdx === modelData.idx
                  color: isCur
                    ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.28)
                    : (optMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.12) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05))
                  border.color: isCur ? root.playerColor : (optMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.50) : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12))
                  border.width: isCur || optMouse.containsMouse ? 1.5 : 1

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Image {
                      width: 16; height: 16
                      anchors.verticalCenter: parent.verticalCenter
                      source: Qt.resolvedUrl(GamepadModel.buttonArt(root.sel ? root.sel.layout : "xbox", modelData.role))
                      fillMode: Image.PreserveAspectFit
                      mipmap: true
                      visible: status === Image.Ready
                      layer.enabled: visible
                      layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: optCard.isCur ? root.playerColor : (optMouse.containsMouse ? root.playerColor : root.barForeground)
                      }
                    }

                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      Text {
                        text: modelData.name
                        color: optCard.isCur ? root.playerColor : (optMouse.containsMouse ? root.playerColor : root.barForeground)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: optCard.isCur
                      }

                      Text {
                        text: "Btn " + modelData.idx
                        color: optCard.isCur ? root.playerColor : Qt.darker(root.barForeground, 1.6)
                        font.family: Style.font.family
                        font.pixelSize: 7
                      }
                    }
                  }

                  MouseArea {
                    id: optMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.applyButtonRemap(remapModal.targetRole, modelData.idx)
                      remapModal.close()
                    }
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)
            }

            // Footer Actions
            Row {
              width: parent.width
              spacing: Style.space(8)

              // Restore Default for this role
              Rectangle {
                width: (parent.width - Style.space(8)) / 2
                height: Style.space(26)
                radius: Math.max(3, Style.cornerRadius - 1)
                color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
                border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "Restore Default"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.applyButtonRemap(remapModal.targetRole, null)
                    remapModal.close()
                  }
                }
              }

              // Done / Cancel button
              Rectangle {
                width: (parent.width - Style.space(8)) / 2
                height: Style.space(26)
                radius: Math.max(3, Style.cornerRadius - 1)
                color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.18)
                border.color: root.playerColor
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "Done / Cancel"
                  color: root.playerColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: remapModal.close()
                }
              }
            }
          }
        }
      }
    }
  }

  // ============================================================ Custom Components

  // ------------------------------------------------------------- Chip
  component Chip : Rectangle {
    id: chip
    property string label: ""
    property string value: ""
    property string sub: ""
    property string iconSource: ""
    property color valueColor: chip.foreground
    property color foreground: Color.foreground

    height: Math.max(Style.space(56), chipCol.implicitHeight + Style.space(12))
    radius: Math.max(4, Style.cornerRadius)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    border.width: 1
    clip: true

    Column {
      id: chipCol
      anchors.centerIn: parent
      width: parent.width - Style.space(12)
      spacing: 2

      Text {
        width: parent.width
        text: chip.label
        color: Qt.darker(chip.foreground, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Row {
        width: parent.width
        spacing: Style.space(4)

        Image {
          visible: chip.iconSource !== ""
          anchors.verticalCenter: parent.verticalCenter
          source: chip.iconSource
          width: 14; height: 14
          fillMode: Image.PreserveAspectFit
        }

        Text {
          width: parent.width - (chip.iconSource !== "" ? Style.space(18) : 0)
          elide: Text.ElideRight
          text: chip.value
          color: chip.valueColor
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        visible: chip.sub !== ""
        text: chip.sub
        color: Qt.darker(chip.foreground, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ------------------------------------------------------------- DeadzoneSlider
  component DeadzoneSlider : Row {
    id: dzRow
    property string labelText: ""
    property real value: 0
    property real minValue: 0
    property real maxValue: 0.50
    property real step: 0.01
    property color foreground: Color.foreground
    property color accent: Color.accent
    signal moved(real v)

    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(115)
      text: dzRow.labelText
      color: dzRow.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    PanelSlider {
      id: slider
      width: Math.max(Style.space(60), parent.width - Style.space(173))
      anchors.verticalCenter: parent.verticalCenter
      minimum: dzRow.minValue
      maximum: dzRow.maxValue
      step: dzRow.step
      value: dzRow.value
      fillColor: dzRow.accent
      knobColor: dzRow.accent
      trackColor: Qt.rgba(dzRow.foreground.r, dzRow.foreground.g, dzRow.foreground.b, 0.18)
      onMoved: function (v) { dzRow.moved(Math.round(v * 100) / 100) }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(42)
      text: Math.round(dzRow.value * 100) + "%"
      color: Qt.darker(dzRow.foreground, 1.3)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
    }
  }

  // ------------------------------------------------------------- RemapPill
  component RemapPill : Rectangle {
    id: rp
    property string role: ""
    property string roleKey: ""
    property string label: ""
    property string svgSource: ""
    property int btnIdx: -1
    property string axisHint: ""
    property bool active: false
    property color accent: root.playerColor
    property color foreground: root.barForeground
    signal clicked()

    height: Style.space(46)
    radius: Math.max(4, Style.cornerRadius - 1)
    scale: active ? 0.95 : (pillMouse.containsMouse ? 1.02 : 1.0)
    color: active
      ? Qt.rgba(accent.r, accent.g, accent.b, 0.28)
      : (pillMouse.containsMouse
          ? Qt.rgba(accent.r, accent.g, accent.b, 0.12)
          : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04))
    border.color: active
      ? accent
      : (pillMouse.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.55) : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12))
    border.width: active || pillMouse.containsMouse ? 1.5 : 1
    clip: true

    Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
    Behavior on color { ColorAnimation { duration: 25 } }
    Behavior on border.color { ColorAnimation { duration: 25 } }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rp.clicked()
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(5)

      // Dynamic SVG Badge for this button
      Item {
        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter
        visible: rp.svgSource !== ""

        Image {
          id: pillSvgImg
          anchors.fill: parent
          source: rp.svgSource
          fillMode: Image.PreserveAspectFit
          mipmap: true
          smooth: true
          visible: rp.svgSource !== "" && status === Image.Ready
          layer.enabled: visible
          layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: rp.active ? rp.accent : (pillMouse.containsMouse ? rp.accent : rp.foreground)
          }
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          text: rp.label
          color: rp.active ? rp.accent : (pillMouse.containsMouse ? rp.accent : rp.foreground)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          text: rp.btnIdx >= 0 ? ("Btn " + rp.btnIdx) : (rp.axisHint !== "" ? rp.axisHint : "Unmapped")
          color: rp.active ? rp.accent : Qt.darker(rp.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: 8
        }
      }
    }

    // Remap edit pencil badge in top-right corner on hover
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 2
      width: 9
      height: 9
      radius: 4.5
      color: Qt.rgba(accent.r, accent.g, accent.b, 0.25)
      visible: pillMouse.containsMouse

      Text {
        anchors.centerIn: parent
        text: "✎"
        font.pixelSize: 6
        color: rp.accent
      }
    }
  }

  // ------------------------------------------------------------- ArtificialHorizon
  component ArtificialHorizon : Rectangle {
    id: ah
    property var gyro: null
    property var bias: null
    property color accent: Color.accent
    property color foreground: Color.foreground
    property real pitchDeg: 0
    property real rollDeg: 0

    radius: Math.max(4, Style.cornerRadius)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
    border.width: 1
    clip: true

    onGyroChanged: updateAngles()
    onBiasChanged: updateAngles()

    function updateAngles() {
      if (!gyro) {
        pitchDeg = 0
        rollDeg = 0
        ahCanvas.requestPaint()
        return
      }
      var ax = Number(gyro.ax) || 0
      var ay = Number(gyro.ay) || 0
      var az = Number(gyro.az) || 9.81

      var pitchRad = -Math.atan2(ay, Math.sqrt(ax * ax + az * az))
      var rollRad = Math.atan2(ax, az)

      pitchDeg = Math.max(-85, Math.min(85, pitchRad * 180 / Math.PI))
      rollDeg = Math.max(-180, Math.min(180, rollRad * 180 / Math.PI))
      ahCanvas.requestPaint()
    }

    Canvas {
      id: ahCanvas
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height) - Style.space(16)
      height: width
      antialiasing: true

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        var cx = width / 2
        var cy = height / 2
        var R = (width / 2) * 0.90

        // Circular clip mask
        ctx.save()
        ctx.beginPath()
        ctx.arc(cx, cy, R, 0, 2 * Math.PI)
        ctx.clip()

        // Roll and Pitch Transform
        ctx.save()
        ctx.translate(cx, cy)
        var rollRad = ah.rollDeg * Math.PI / 180
        ctx.rotate(-rollRad)

        var pitchPx = (ah.pitchDeg / 90) * R * 0.85

        // Sky half
        ctx.fillStyle = Qt.rgba(0.14, 0.40, 0.72, 0.65)
        ctx.fillRect(-R * 2, -R * 2, R * 4, R * 2 + pitchPx)

        // Ground half
        ctx.fillStyle = Qt.rgba(0.38, 0.24, 0.16, 0.70)
        ctx.fillRect(-R * 2, pitchPx, R * 4, R * 2)

        // Horizon line
        ctx.beginPath()
        ctx.moveTo(-R * 1.5, pitchPx)
        ctx.lineTo(R * 1.5, pitchPx)
        ctx.lineWidth = 2
        ctx.strokeStyle = "#FFFFFF"
        ctx.stroke()

        // Pitch ladder lines
        var steps = [-40, -20, -10, 10, 20, 40]
        ctx.lineWidth = 1.5
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.75)
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.85)
        ctx.font = "8px sans-serif"
        ctx.textAlign = "center"

        for (var s = 0; s < steps.length; s++) {
          var deg = steps[s]
          var y = pitchPx - (deg / 90) * R * 0.85
          var w = Math.abs(deg) === 20 || Math.abs(deg) === 40 ? 22 : 14

          ctx.beginPath()
          ctx.moveTo(-w, y)
          ctx.lineTo(w, y)
          ctx.stroke()

          ctx.fillText(Math.abs(deg).toString(), w + 8, y + 3)
          ctx.fillText(Math.abs(deg).toString(), -w - 8, y + 3)
        }

        ctx.restore() // End of pitch/roll transform

        // Bezel outline
        ctx.beginPath()
        ctx.arc(cx, cy, R, 0, 2 * Math.PI)
        ctx.lineWidth = 2
        ctx.strokeStyle = Qt.rgba(ah.foreground.r, ah.foreground.g, ah.foreground.b, 0.3)
        ctx.stroke()

        ctx.restore() // End of clip mask

        // Fixed Aircraft Reticle
        ctx.strokeStyle = ah.accent
        ctx.lineWidth = 2.5

        ctx.beginPath()
        ctx.moveTo(cx - 24, cy)
        ctx.lineTo(cx - 8, cy)
        ctx.lineTo(cx - 8, cy + 4)
        ctx.stroke()

        ctx.beginPath()
        ctx.moveTo(cx + 24, cy)
        ctx.lineTo(cx + 8, cy)
        ctx.lineTo(cx + 8, cy + 4)
        ctx.stroke()

        ctx.beginPath()
        ctx.arc(cx, cy, 3, 0, 2 * Math.PI)
        ctx.fillStyle = ah.accent
        ctx.fill()
      }
    }

    Row {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      Text {
        text: "Pitch: " + (ah.pitchDeg >= 0 ? "+" : "") + ah.pitchDeg.toFixed(1) + "°"
        color: ah.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Row {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      Text {
        text: "Roll: " + (ah.rollDeg >= 0 ? "+" : "") + ah.rollDeg.toFixed(1) + "°"
        color: ah.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  // ------------------------------------------------------------- BiBar
  component BiBar : Item {
    id: bb
    property string label: ""
    property real val: 0.0
    property real maxAbs: 20.0
    property string unit: ""
    property color accent: root.playerColor
    property color foreground: root.barForeground
    readonly property real normVal: Math.max(-1, Math.min(1, bb.val / Math.max(0.1, bb.maxAbs)))

    height: Style.space(18)
    width: parent.width

    Row {
      anchors.fill: parent
      spacing: Style.space(6)

      Text {
        width: Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        text: bb.label
        color: bb.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Rectangle {
        id: track
        width: Math.max(Style.space(40), parent.width - Style.space(89))
        height: Style.space(7)
        anchors.verticalCenter: parent.verticalCenter
        radius: 3.5
        color: Qt.rgba(bb.foreground.r, bb.foreground.g, bb.foreground.b, 0.08)

        // Center line
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 1; height: parent.height
          color: Qt.rgba(bb.foreground.r, bb.foreground.g, bb.foreground.b, 0.3)
        }

        // Dynamic fill from center
        Rectangle {
          height: parent.height
          radius: 3.5
          x: bb.normVal >= 0 ? parent.width / 2 : parent.width / 2 + bb.normVal * (parent.width / 2)
          width: Math.abs(bb.normVal) * (parent.width / 2)
          color: bb.accent
        }
      }

      Text {
        width: Style.space(55)
        anchors.verticalCenter: parent.verticalCenter
        text: (bb.val >= 0 ? "+" : "") + bb.val.toFixed(1) + " " + bb.unit
        color: bb.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
      }
    }
  }

  // ------------------------------------------------------------- SpecRow
  component SpecRow : Rectangle {
    id: sr
    property string label: ""
    property string value: ""
    property string iconSource: ""
    property color foreground: root.barForeground

    width: parent.width
    height: Style.space(28)
    radius: Math.max(4, Style.cornerRadius)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    border.width: 1
    clip: true

    Item {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)

      Image {
        id: srIcon
        visible: sr.iconSource !== ""
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        source: sr.iconSource
        width: visible ? 16 : 0
        height: 16
        fillMode: Image.PreserveAspectFit
      }

      Text {
        id: srLabel
        anchors.left: srIcon.visible ? srIcon.right : parent.left
        anchors.leftMargin: srIcon.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(135)
        text: sr.label
        color: Qt.darker(sr.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        anchors.left: srLabel.right
        anchors.leftMargin: Style.space(6)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: sr.value
        color: sr.foreground
        font.family: Style.font.family
        font.pixelSize: sr.value.length > 50 ? 8 : Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }
}
