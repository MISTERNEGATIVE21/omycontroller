import QtQuick
import Quickshell
import Quickshell.Io
import "GamepadModel.js" as GamepadModel

// Quatro — Service.qml
//
// Headless gamepad service (plugin kind: service). The Quattro host mounts
// this singleton when the plugin is enabled, so the bar pill keeps battery
// and status fresh even while the panel is closed, and the panel attaches
// to the very same state without spawning anything.
//
// Responsibilities:
//   - poll sysfs via scripts/scan.sh every scanIntervalMs (devices, battery,
//     driver, bustype, evdev node, motion-sensor node)
//   - keep one `jstest --event` stream per connected pad for live button /
//     axis state and real input latency (evdev event-interval average)
//   - keep one scripts/gyro.py stream per pad that has a motion sensor
//     (accelerometer + gyro snapshots, stdlib-only reader)
//   - persist per-pad deadzone profiles, gyro drift offsets and rumble
//     strength (PersistentProperties)
//   - best-effort hardware actions: rumble test (python-evdev) and DualSense
//     adaptive-trigger modes (hidraw)
//
// Consumers reach it through the host facade:
//   shell.serviceFor("quatro.gamepad")   (scoped to this plugin — correct
//   for third-party plugins; first-party bar shells inject the same shape)
//
// State model: `devices` is a JS map (id -> device state). Structural or
// battery updates reassign the map so readonly bindings recompute; the
// high-frequency per-event fields (buttons/axes/latency) are mutated in
// place and announced through liveUpdated(id) so the panel's art can redraw
// without churning the binding tree.

Item {
  id: root

  // Injected by the Quattro host when the entry point declares the property.
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- config
  readonly property string pluginId: "quatro.gamepad"
  property int scanIntervalMs: 2000
  property int lowBatteryThreshold: 15
  readonly property int maxSlots: 4

  // ------------------------------------------------------------------ urls
  // Scripts ship inside the plugin folder; resolve through the QML file URL
  // so this works from ~/.config/omarchy/plugins and first-party checkouts.
  readonly property string scanScript: root.localPath("scripts/scan.sh")
  readonly property string rumbleScript: root.localPath("scripts/rumble.py")
  readonly property string triggersScript: root.localPath("scripts/triggers.py")
  readonly property string gyroScript: root.localPath("scripts/gyro.py")

  function localPath(rel) {
    var url = Qt.resolvedUrl(rel).toString()
    var path = url.replace(/^file:\/\//, "")
    try { path = decodeURIComponent(path) } catch (e) {}
    return path
  }

  // ------------------------------------------------------------------ state
  readonly property var devices: _devices
  property var _devices: ({})
  property var _streams: ({})          // jsN -> jstest Process
  property var _gyroStreams: ({})      // jsN -> gyro.py Process
  property var slotById: ({})          // jsN -> 1..4, stable per session

  readonly property var deviceList: {
    var list = []
    for (var id in _devices) list.push(_devices[id])
    list.sort(function (a, b) { return a.slot - b.slot || (a.id < b.id ? -1 : 1) })
    return list
  }
  readonly property int count: deviceList.length
  readonly property bool hasDualSense: {
    for (var i = 0; i < deviceList.length; i++) {
      var d = deviceList[i]
      if (d.layout === "ps" && String(d.protocol).indexOf("DualSense") !== -1) return true
    }
    return false
  }

  // Tool availability, filled by envProc on startup.
  property bool jstestAvailable: false
  property bool evdevAvailable: false
  readonly property bool liveInputReady: jstestAvailable && count > 0

  // Last hardware-action feedback line for the panel footer.
  signal actionResult(string message)
  signal devicesChanged()
  signal liveUpdated(string id)

  // Per-pad deadzone profiles, persisted across reloads and restarts.
  PersistentProperties {
    id: persisted
    reloadableId: "quatro-gamepad"
    property var profiles: ({})
  }

  // -------------------------------------------------------------- helpers
  function device(id) {
    return _devices[String(id)] || null
  }

  function playerSlot(id) {
    var s = slotById[String(id)]
    return s ? s : 0
  }

  function classifyDevice(d) {
    return GamepadModel.classify(d.name, d.driver, d.vendor, d.product,
                                 d.axisCount, d.buttonCount)
  }

  function connectionOf(d) {
    return GamepadModel.connection(d.bus, d.name, d.phys)
  }

  function profileFor(id) {
    var d = device(id)
    var key = d ? GamepadModel.profileKey(d.vendor, d.product, d.name) : ""
    var raw = key && persisted.profiles ? persisted.profiles[key] : null
    var p = GamepadModel.normalizeProfile(raw)
    if (raw) {
      if (raw.gyroBias && typeof raw.gyroBias === "object") {
        p.gyroBias = {
          x: isFinite(Number(raw.gyroBias.x)) ? Number(raw.gyroBias.x) : 0,
          y: isFinite(Number(raw.gyroBias.y)) ? Number(raw.gyroBias.y) : 0,
          z: isFinite(Number(raw.gyroBias.z)) ? Number(raw.gyroBias.z) : 0
        }
      }
      var r = Number(raw.rumble)
      p.rumble = isFinite(r) ? Math.min(1, Math.max(0.1, r)) : 1
    } else {
      p.rumble = 1
    }
    return p
  }

  // Store deadzone values plus any extras (gyroBias, rumble) without ever
  // dropping fields the previous write had saved.
  function storeProfile(d, values) {
    var pk = GamepadModel.profileKey(d.vendor, d.product, d.name)
    var all = {}
    for (var k in persisted.profiles) all[k] = persisted.profiles[k]
    var prev = all[pk] || {}
    var p = GamepadModel.normalizeProfile(prev)
    var r = Number(prev.rumble)
    p.rumble = isFinite(r) ? Math.min(1, Math.max(0.1, r)) : 1
    if (prev.gyroBias && typeof prev.gyroBias === "object") p.gyroBias = prev.gyroBias
    for (var e in values) p[e] = values[e]
    all[pk] = p
    persisted.profiles = all
    d.profile = p
    _touch(d.id)
  }

  function setDeadzone(id, key, value) {
    var d = device(id)
    if (!d) return false
    var n = Number(value)
    if (!isFinite(n)) return false
    storeProfile(d, (function () { var v = {}; v[key] = Math.min(0.5, Math.max(0, n)); return v })())
    tryXpadneoApply(d, d.profile)
    return true
  }

  // Per-pad rumble power for the test buttons (0.1..1, persisted).
  function setRumble(id, value) {
    var d = device(id)
    if (!d) return false
    var n = Number(value)
    if (!isFinite(n)) return false
    storeProfile(d, { rumble: Math.min(1, Math.max(0.1, n)) })
    root.actionResult("Rumble power stored for " + d.modelLabel)
    return true
  }

  // Gyro drift calibration: average ~0.8s of stationary samples and store
  // the offsets per pad. The panel subtracts them from the live gauge.
  function calibrateGyro(id) {
    var d = device(id)
    if (!d) return false
    if (!d.motionNode || d.motionNode === "") {
      root.actionResult("No motion sensor on " + d.modelLabel)
      return false
    }
    if (!_gyroStreams[id]) {
      root.actionResult("Gyro stream not running yet — try again in a second")
      return false
    }
    d._gyroCal = []
    root.actionResult("Calibrating gyro — keep the pad still…")
    return true
  }

  // xpadneo exposes per-controller knobs under
  // /sys/module/hid_xpadneo/controllers/<hdev>/. Rather than guessing at
  // driver-specific knobs we store the profile (it shapes the live preview
  // and any sysfs shim reads it from the panel footer output).
  function tryXpadneoApply(d, p) {
    root.actionResult("Deadzone stored for " + d.modelLabel + " — live preview updated")
  }

  function _touch(id) {
    // Reassign the map so readonly bindings (deviceList, count) refresh.
    var next = ({})
    for (var k in _devices) next[k] = _devices[k]
    _devices = next
    devicesChanged()
  }

  // ------------------------------------------------------------ scan cycle
  Timer {
    id: scanTimer
    interval: root.scanIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runScan()
  }

  Process {
    id: scanProc
    stdout: SplitParser {
      onRead: function (line) { root.ingestScanLine(line) }
    }
    onExited: root.reconcileStreams()
  }

  function runScan() {
    if (scanProc.running) return
    scanProc.command = ["bash", root.scanScript]
    scanProc.running = true
  }

  function ingestScanLine(line) {
    var raw = String(line || "").trim()
    if (raw.length === 0) return
    var rec
    try { rec = JSON.parse(raw) } catch (e) { return }
    if (!rec || !rec.id) return
    var id = String(rec.id)
    var existing = _devices[id]

    var state = existing || {
      id: id,
      slot: 0,
      buttons: {},
      buttonCount: 0,
      axes: [],
      axisCount: 0,
      axisNames: [],
      avgMs: -1,
      eps: 0,
      _lastTs: -1,
      _samples: []
    }

    state.input = String(rec.input || "")
    state.event = String(rec.event || "")
    state.name = String(rec.name || id)
    state.driver = String(rec.driver || "?")
    state.bus = String(rec.bus || "0000")
    state.vendor = String(rec.vendor || "0000")
    state.product = String(rec.product || "0000")
    state.phys = String(rec.phys || "")
    state.percent = (rec.percent === undefined || rec.percent === null) ? -1 : Number(rec.percent)
    state.charging = !!rec.charging
    state.motionNode = String(rec.motion || "")
    var cls = GamepadModel.classify(state.name, state.driver, state.vendor, state.product,
                                    state.axisCount, state.buttonCount)
    state.layout = cls.layout
    state.modelLabel = cls.modelLabel
    state.protocol = cls.protocol
    state.maker = cls.maker
    state.connection = GamepadModel.connection(state.bus, state.name, state.phys)
    state.profile = root.profileFor(id)

    if (!existing) {
      state.slot = root.claimSlot(id)
      var next = ({})
      for (var k in _devices) next[k] = _devices[k]
      next[id] = state
      _devices = next
      devicesChanged()
      root.startStream(id)
    } else if (existing.percent !== state.percent || existing.charging !== state.charging ||
               existing.motionNode !== state.motionNode) {
      _touch(id)
    }
  }

  function claimSlot(id) {
    if (slotById[id]) return slotById[id]
    var taken = {}
    for (var other in slotById) taken[slotById[other]] = true
    for (var s = 1; s <= root.maxSlots; s++) {
      if (!taken[s]) { slotById[id] = s; return s }
    }
    slotById[id] = root.maxSlots
    return root.maxSlots
  }

  function releaseSlot(id) { delete slotById[id] }

  // ----------------------------------------------------- jstest event streams
  Component {
    id: streamComp
    Process {
      property string targetId: ""
      stdout: SplitParser {
        onRead: function (line) { root.handleEventLine(targetId, line) }
      }
      stderr: StdioCollector { }
      onExited: root.streamDied(targetId)
    }
  }

  function startStream(id) {
    if (!root.jstestAvailable) return
    if (_streams[id]) return
    var d = device(id)
    if (!d) return
    var proc = streamComp.createObject(root, { targetId: id })
    if (!proc) return
    proc.command = ["jstest", "--event", "/dev/input/" + id]
    proc.running = true
    var next = ({})
    for (var k in _streams) next[k] = _streams[k]
    next[id] = proc
    _streams = next
  }

  function stopStream(id) {
    var proc = _streams[id]
    if (!proc) return
    var next = ({})
    for (var k in _streams) if (k !== id) next[k] = _streams[k]
    _streams = next
    if (proc.running) proc.running = false
    proc.destroy()
  }

  function reconcileStreams() {
    for (var id in _devices) {
      root.startStream(id)
      root.startGyroStream(id)
    }
    for (var sid in _streams) {
      if (!_devices[sid]) root.stopStream(sid)
    }
    for (var gid in _gyroStreams) {
      var d = _devices[gid]
      if (!d || d.motionNode !== _gyroStreams[gid].node) root.stopGyroStream(gid)
    }
  }

  function streamDied(id) {
    // Device unplugged (or jstest vanished). The next scan sweep cleans the
    // state; drop the process handle immediately.
    if (_streams[id] && !_devices[id]) stopStream(id)
  }

  // ------------------------------------------------------- gyro/motion streams
  Component {
    id: gyroComp
    Process {
      property string targetId: ""
      property string node: ""
      stdout: SplitParser {
        onRead: function (line) { root.handleGyroLine(targetId, line) }
      }
      stderr: StdioCollector { }
      onExited: root.gyroDied(targetId)
    }
  }

  function startGyroStream(id) {
    var d = device(id)
    if (!d || !d.motionNode || d.motionNode === "") return
    if (_gyroStreams[id]) return
    var proc = gyroComp.createObject(root, { targetId: id, node: d.motionNode })
    if (!proc) return
    proc.command = ["python3", root.gyroScript, "/dev/input/" + d.motionNode]
    proc.running = true
    var next = ({})
    for (var k in _gyroStreams) next[k] = _gyroStreams[k]
    next[id] = proc
    _gyroStreams = next
  }

  function stopGyroStream(id) {
    var proc = _gyroStreams[id]
    if (!proc) return
    var next = ({})
    for (var k in _gyroStreams) if (k !== id) next[k] = _gyroStreams[k]
    _gyroStreams = next
    if (proc.running) proc.running = false
    proc.destroy()
  }

  function gyroDied(id) {
    var d = _devices[id]
    if (_gyroStreams[id] && (!d || !d.motionNode || d.motionNode === "")) stopGyroStream(id)
  }

  function handleGyroLine(id, line) {
    var d = device(id)
    if (!d) return
    var rec
    try { rec = JSON.parse(String(line || "")) } catch (e) { return }
    if (!rec) return
    d.gyro = {
      ax: Number(rec.ax) || 0, ay: Number(rec.ay) || 0, az: Number(rec.az) || 0,
      gx: Number(rec.gx) || 0, gy: Number(rec.gy) || 0, gz: Number(rec.gz) || 0,
      afs: Number(rec.afs) || 32767, gfs: Number(rec.gfs) || 32767
    }
    // Drift calibration collection: ~0.8s of stationary samples.
    if (d._gyroCal) {
      d._gyroCal.push([d.gyro.gx, d.gyro.gy, d.gyro.gz])
      if (d._gyroCal.length >= 20) {
        var sx = 0, sy = 0, sz = 0
        for (var i = 0; i < d._gyroCal.length; i++) {
          sx += d._gyroCal[i][0]
          sy += d._gyroCal[i][1]
          sz += d._gyroCal[i][2]
        }
        var n = d._gyroCal.length
        storeProfile(d, { gyroBias: { x: sx / n, y: sy / n, z: sz / n } })
        d._gyroCal = null
        root.actionResult("Gyro calibrated for " + d.modelLabel + " — drift offset stored")
      }
    }
    liveUpdated(id)
  }

  // jstest prints either "code N" or "number N" depending on version;
  // accept both so live input survives across distros. The header regex
  // also captures the axis-name list ("X, Y, Throttle, Hat0X, Hat0Y") so
  // joystick extras bind by name, not by guessed index.
  readonly property var eventRe: /time\s+([0-9]+\.[0-9]+).*?type\s+(\d+).*?(?:code|number)\s+(\d+).*?value\s+(-?\d+)/
  readonly property var headerRe: /has\s+(\d+)\s+axes\s*\(([^)]*)\)\s+and\s+(\d+)\s+buttons/

  function handleEventLine(id, line) {
    var d = device(id)
    if (!d) return
    var text = String(line || "")

    if (text.indexOf("axes") !== -1 && text.indexOf("has") !== -1) {
      var header = headerRe.exec(text)
      if (header) {
        d.axisCount = parseInt(header[1], 10)
        d.buttonCount = parseInt(header[3], 10)
        d.axisNames = String(header[2] || "")
          .split(",")
          .map(function (s) { return s.trim() })
          .filter(function (s) { return s.length > 0 })
        if (d.axes.length !== d.axisCount) {
          var fresh = []
          for (var i = 0; i < d.axisCount; i++) fresh.push(0)
          d.axes = fresh
        }
        d.live = true
        // Shape facts just arrived — re-classify so plain joysticks switch
        // from the generic gamepad silhouette to the dedicated one.
        var cls = GamepadModel.classify(d.name, d.driver, d.vendor, d.product,
                                        d.axisCount, d.buttonCount)
        if (cls.layout !== d.layout || cls.protocol !== d.protocol ||
            cls.modelLabel !== d.modelLabel) {
          d.layout = cls.layout
          d.modelLabel = cls.modelLabel
          d.protocol = cls.protocol
          d.maker = cls.maker
        }
        _touch(id)
      }
      return
    }

    var m = eventRe.exec(text)
    if (!m) return
    var ts = parseFloat(m[1])
    var type = parseInt(m[2], 10) & 0x7f
    var num = parseInt(m[3], 10)
    var value = parseInt(m[4], 10)

    if (type === 1) {
      d.buttons[num] = (value !== 0)
      liveUpdated(id)
    } else if (type === 2) {
      while (d.axes.length <= num) d.axes.push(0)
      d.axes[num] = value / 32767.0
      liveUpdated(id)
    }

    // Input latency: rolling average of evdev event intervals.
    if (!isNaN(ts)) {
      if (d._lastTs > 0) {
        var delta = (ts - d._lastTs) * 1000.0
        if (delta > 0 && delta < 1000) {
          d._samples.push(delta)
          if (d._samples.length > 24) d._samples.shift()
          var sum = 0
          for (var s = 0; s < d._samples.length; s++) sum += d._samples[s]
          d.avgMs = sum / d._samples.length
          d.eps = d.avgMs > 0 ? 1000.0 / d.avgMs : 0
        }
      }
      d._lastTs = ts
    }
  }

  // ------------------------------------------------------- hardware actions
  Process {
    id: actionProc
    property string kind: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._actionStderr = text
    }
    onExited: {
      var msg = "ok"
      if (exitCode !== 0) msg = String(root._actionStderr || "").trim() || ("failed (exit " + exitCode + ")")
      root.actionResult(msg)
    }
  }
  property string _actionStderr: ""

  function runAction(argv, kind) {
    if (actionProc.running) {
      root.actionResult("Another action is still running")
      return false
    }
    actionProc.kind = kind
    root._actionStderr = ""
    actionProc.command = argv
    actionProc.running = true
    return true
  }

  // Rumble test: weak/strong magnitudes in 0..1, duration in ms. The
  // per-pad stored power profile scales both motors.
  function rumble(id, weak, strong, ms) {
    var d = device(id)
    if (!d || !d.event) {
      root.actionResult("No evdev node for " + id)
      return false
    }
    if (!root.evdevAvailable) {
      root.actionResult("python-evdev missing — sudo pacman -S --needed python-evdev")
      return false
    }
    var strength = d.profile && isFinite(Number(d.profile.rumble))
        ? Math.min(1, Math.max(0.1, Number(d.profile.rumble))) : 1
    var w = Math.round(Math.min(1, Math.max(0, weak)) * strength * 65535)
    var s = Math.round(Math.min(1, Math.max(0, strong)) * strength * 65535)
    return runAction(
      ["python3", root.rumbleScript, "/dev/input/" + d.event,
       String(w), String(s), String(Math.max(30, ms))],
      "rumble")
  }

  // DualSense adaptive triggers: left/right in
  // off|weak|medium|strong|rigid|pulse.
  function setTriggers(id, leftMode, rightMode) {
    var d = device(id)
    if (!d || d.layout !== "ps") {
      root.actionResult("Adaptive triggers need a DualSense pad")
      return false
    }
    return runAction(
      ["python3", root.triggersScript, "auto", leftMode, rightMode],
      "triggers")
  }

  // ------------------------------------------------------------ env probing
  Process {
    id: envProc
    command: ["sh", "-c",
      "command -v jstest >/dev/null 2>&1 && printf 'jstest:yes\\n' || printf 'jstest:no\\n'; " +
      "python3 -c 'import evdev' >/dev/null 2>&1 && printf 'evdev:yes\\n' || printf 'evdev:no\\n'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "")
        root.jstestAvailable = t.indexOf("jstest:yes") !== -1
        root.evdevAvailable = t.indexOf("evdev:yes") !== -1
      }
    }
  }

  Component.onCompleted: envProc.running = true
  Component.onDestruction: {
    for (var id in _streams) stopStream(id)
    for (var gid in _gyroStreams) stopGyroStream(gid)
  }
}
