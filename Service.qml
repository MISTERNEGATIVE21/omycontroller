import QtQuick
import Quickshell
import Quickshell.Io
import "GamepadModel.js" as GamepadModel

// omycontroller — Service.qml
//
// Headless gamepad service (plugin kind: service). The shell mounts
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
//   - interactive virtual simulator engine (`demoMode` / `simulatorActive`)
//   - live latency (min/avg/max ms) and polling rate (Hz) benchmark tracking
//   - persist per-pad deadzone profiles, gyro drift offsets and rumble
//     strength (PersistentProperties)
//   - best-effort hardware actions: rumble test (python-evdev) and DualSense
//     adaptive-trigger modes (hidraw)
//
// Consumers reach it through the host facade:
//   shell.serviceFor("omycontroller")   (scoped to this plugin)
//
// State model: `devices` is a JS map (id -> device state). Structural or
// battery updates reassign the map so readonly bindings recompute; the
// high-frequency per-event fields (buttons/axes/latency) are mutated in
// place and announced through liveUpdated(id) so the panel's art can redraw
// without churning the binding tree.

Item {
  id: root

  // Injected by the host when the entry point declares the property.
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- config
  readonly property string pluginId: "omycontroller"
  property int scanIntervalMs: 2000
  property int lowBatteryThreshold: 15
  readonly property int maxSlots: 4

  // Simulator / Demo mode properties
  property bool demoMode: false
  property bool simulatorActive: false
  onDemoModeChanged: {
    if (simulatorActive !== demoMode) simulatorActive = demoMode
    if (demoMode) root.startSimulator()
    else root.stopSimulator()
  }
  onSimulatorActiveChanged: {
    if (demoMode !== simulatorActive) demoMode = simulatorActive
  }

  IpcHandler {
    target: "omycontroller-service"

    function rescan() {
      root.rescan()
    }

    function setRumble(target: string, weakOrValue: real, strong: real): bool {
      return root.setRumble(target, weakOrValue, strong)
    }

    function calibrateGyro(target: string): bool {
      return root.calibrateGyro(target)
    }

    function setDeadzone(target: string, key: string, value: real): bool {
      return root.setDeadzone(target, key, value)
    }

    function toggleDemo(): bool {
      return root.toggleDemo()
    }

    function cycleDemoLayout(): string {
      return root.cycleDemoLayout()
    }
  }

  // Live polling rate (Hz) and min/avg/max latency benchmark stats
  property var stats: computeStats()

  function computeStats() {
    var target = null
    for (var id in _devices) {
      if (_devices[id].slot === 1) { target = _devices[id]; break }
    }
    if (!target && deviceList.length > 0) target = deviceList[0]

    if (!target || !target.avgMs || target.avgMs <= 0) {
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

    var lat = GamepadModel.latencyMetrics(target._samples && target._samples.length ? target._samples : [target.avgMs])
    var hzVal = target.eps ? Math.round(target.eps) : lat.hz
    return {
      hz: hzVal,
      pollingRate: hzVal,
      avg: target.avgMs || lat.avg,
      avgMs: target.avgMs || lat.avg,
      min: target.minMs !== undefined ? target.minMs : lat.min,
      minMs: target.minMs !== undefined ? target.minMs : lat.min,
      max: target.maxMs !== undefined ? target.maxMs : lat.max,
      maxMs: target.maxMs !== undefined ? target.maxMs : lat.max,
      jitter: target.jitter !== undefined ? target.jitter : lat.jitter,
      formattedHz: GamepadModel.formatHz(target.avgMs || lat.avg),
      label: lat.label
    }
  }

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
  signal liveUpdated(string id)

  // Per-pad deadzone profiles, persisted across reloads and restarts.
  PersistentProperties {
    id: persisted
    reloadableId: "omycontroller"
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
    var allowedKeys = ["stickL", "stickR", "trigL", "trigR"]
    var k = String(key || "")
    if (allowedKeys.indexOf(k) === -1) return false
    var n = Number(value)
    if (!isFinite(n)) return false
    var v = {}
    v[k] = Math.min(0.5, Math.max(0.0, n))
    storeProfile(d, v)
    tryXpadneoApply(d, d.profile)
    return true
  }

  // -------------------------------------------------------- IPC handlers
  function toggleDemo() {
    root.demoMode = !root.demoMode
    return root.demoMode
  }

  function cycleDemoLayout() {
    if (!root.demoMode) {
      root.demoMode = true
    } else {
      var d = _devices["sim:1"]
      if (d) {
        if (d.layout === "xbox") {
          d.layout = "ps"
          d.modelLabel = "DualSense Wireless Controller (Simulated)"
          d.maker = "Sony"
          d.protocol = "DualSense (Simulated)"
          d.vendor = "054c"
          d.product = "0ce6"
        } else if (d.layout === "ps") {
          d.layout = "switch"
          d.modelLabel = "Nintendo Switch Pro Controller (Simulated)"
          d.maker = "Nintendo"
          d.protocol = "SwitchPro (Simulated)"
          d.vendor = "057e"
          d.product = "2009"
        } else {
          d.layout = "xbox"
          d.modelLabel = "Xbox Wireless Controller (Simulated)"
          d.maker = "Microsoft"
          d.protocol = "XInput (Simulated)"
          d.vendor = "045e"
          d.product = "0b12"
        }
        root.devicesChanged()
      }
    }
    return true
  }

  function rescan() {
    root.runScan()
  }

  // Per-pad rumble power preference or trigger action: setRumble(slotOrId, weak, strong)
  function setRumble(target, weakOrValue, strong) {
    var d = null
    if (target !== undefined && target !== null && (typeof target === "number" || /^[1-4]$/.test(String(target)))) {
      var slotNum = parseInt(target, 10)
      for (var k in _devices) {
        if (_devices[k].slot === slotNum) {
          d = _devices[k]
          break
        }
      }
    }
    if (!d && target) {
      d = device(target)
    }
    if (!d) {
      for (var j in _devices) {
        if (_devices[j].slot === 1) { d = _devices[j]; break }
      }
      if (!d && deviceList.length > 0) d = deviceList[0]
    }
    if (!d) return false

    // Action trigger: setRumble(slot, weak, strong)
    if (strong !== undefined && strong !== null) {
      var w = Number(weakOrValue)
      var s = Number(strong)
      if (!isFinite(w)) w = 1.0
      if (!isFinite(s)) s = w
      if (d.id === "sim0") {
        root.actionResult("Rumble simulated (" + Math.round(w * 100) + "% / " + Math.round(s * 100) + "%) on " + d.modelLabel)
        return true
      }
      return root.rumble(d.id, w, s, 500)
    }

    // Single value: store rumble power preference
    var n = Number(weakOrValue)
    if (!isFinite(n)) return false
    storeProfile(d, { rumble: Math.min(1, Math.max(0.1, n)) })
    root.actionResult("Rumble power stored for " + d.modelLabel)
    return true
  }

  // Gyro drift calibration: average ~0.8s of stationary samples and store
  // the offsets per pad. The panel subtracts them from the live gauge.
  function calibrateGyro(target) {
    var d = null
    if (target !== undefined && target !== null && (typeof target === "number" || /^[1-4]$/.test(String(target)))) {
      var slotNum = parseInt(target, 10)
      for (var id in _devices) {
        if (_devices[id].slot === slotNum) {
          d = _devices[id]
          break
        }
      }
    }
    if (!d && target) {
      d = device(target)
    }
    if (!d) {
      for (var k in _devices) {
        if (_devices[k].slot === 1) { d = _devices[k]; break }
      }
      if (!d && deviceList.length > 0) d = deviceList[0]
    }
    if (!d) return false
    var devId = d.id
    if (devId === "sim0") {
      d._gyroCal = []
      root.actionResult("Calibrating gyro for " + d.modelLabel + " (Simulated)…")
      return true
    }
    if (!d.motionNode || d.motionNode === "") {
      root.actionResult("No motion sensor on " + d.modelLabel)
      return false
    }
    if (!_gyroStreams[devId]) {
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
    root.stats = computeStats()
    devicesChanged()
  }

  // -------------------------------------------------------- simulator engine
  property double _simTick: 0

  Timer {
    id: simTimer
    interval: 16 // 60 Hz (~16.67ms)
    running: root.demoMode
    repeat: true
    onTriggered: root.updateSimulator()
  }

  function startSimulator() {
    if (_devices["sim0"]) {
      simTimer.running = true
      return
    }
    var sim = {
      id: "sim0",
      slot: 1,
      input: "sim0",
      event: "event_sim0",
      name: "Xbox Wireless Controller (Simulated)",
      driver: "xpadneo",
      driverNote: "simulated",
      bus: "0005",
      vendor: "045e",
      product: "0b12",
      phys: "e4:17:d8:sim",
      percent: 88,
      charging: false,
      motionNode: "event_sim_motion",
      layout: "xbox",
      modelLabel: "Xbox Wireless Controller (Simulated)",
      protocol: "XInput (Simulated)",
      maker: "Microsoft",
      connection: "Bluetooth",
      buttonCount: 16,
      buttons: {},
      axisCount: 6,
      axes: [0, 0, 0, 0, -1, -1],
      axisNames: ["X", "Y", "Z", "Rx", "Ry", "Rz"],
      live: true,
      avgMs: 2.0,
      eps: 500,
      minMs: 1.8,
      maxMs: 2.2,
      jitter: 0.08,
      pollingRate: 500,
      _lastTs: -1,
      _samples: [2.0, 1.9, 2.1, 2.0, 2.0, 1.9, 2.1, 2.0],
      gyro: {
        ax: 0, ay: 0, az: 9.81,
        gx: 0, gy: 0, gz: 0,
        afs: 32767, gfs: 32767
      },
      profile: {
        stickL: 0.10,
        stickR: 0.10,
        trigL: 0.05,
        trigR: 0.05,
        rumble: 1.0,
        gyroBias: { x: 0, y: 0, z: 0 }
      }
    }
    slotById["sim0"] = 1
    var next = {}
    for (var k in _devices) next[k] = _devices[k]
    next["sim0"] = sim
    _devices = next
    simTimer.running = true
    root.stats = computeStats()
    devicesChanged()
  }

  function stopSimulator() {
    simTimer.running = false
    if (_devices["sim0"]) {
      var next = {}
      for (var k in _devices) {
        if (k !== "sim0") next[k] = _devices[k]
      }
      _devices = next
      delete slotById["sim0"]
      root.stats = computeStats()
      devicesChanged()
    }
  }

  function updateSimulator() {
    var sim = _devices["sim0"]
    if (!sim) return

    _simTick += 0.04

    // 1. Orbiting left & right sticks (circular paths testing circularity radar)
    // Left stick orbits around boundary with slight variance (0.95 - 1.0)
    var rL = 0.96 + 0.04 * Math.sin(_simTick * 3.0)
    var lx = rL * Math.cos(_simTick)
    var ly = rL * Math.sin(_simTick)

    // Right stick counter-orbits with distinct speed
    var rR = 0.92 + 0.08 * Math.cos(_simTick * 2.0)
    var rx = rR * Math.cos(-_simTick * 1.3)
    var ry = rR * Math.sin(-_simTick * 1.3)

    sim.axes[0] = Math.max(-1.0, Math.min(1.0, lx))
    sim.axes[1] = Math.max(-1.0, Math.min(1.0, ly))
    sim.axes[2] = Math.max(-1.0, Math.min(1.0, rx))
    sim.axes[3] = Math.max(-1.0, Math.min(1.0, ry))

    // 2. Ramping LT/RT triggers (-1..1 maps to 0..1 via triggerNorm)
    sim.axes[4] = Math.sin(_simTick * 1.5)
    sim.axes[5] = Math.cos(_simTick * 1.2)

    // 3. Cycling A/B/X/Y button presses and bumpers
    var cycle = Math.floor(_simTick * 1.5) % 8
    var btn = {}
    if (cycle === 0) btn[0] = true       // A
    else if (cycle === 1) btn[1] = true  // B
    else if (cycle === 2) btn[2] = true  // X
    else if (cycle === 3) btn[3] = true  // Y
    else if (cycle === 4) btn[4] = true  // LB
    else if (cycle === 5) btn[5] = true  // RB
    else if (cycle === 6) btn[11] = true // D-pad Up
    sim.buttons = btn

    // 4. Sinusoidal gyro pitch/roll stream
    sim.gyro = {
      ax: 2.0 * Math.sin(_simTick * 2.0),
      ay: 2.0 * Math.cos(_simTick * 2.0),
      az: 9.81 + 0.5 * Math.sin(_simTick),
      gx: 30.0 * Math.sin(_simTick * 2.5),
      gy: 25.0 * Math.cos(_simTick * 2.0),
      gz: 15.0 * Math.sin(_simTick * 1.5),
      afs: 32767,
      gfs: 32767
    }

    if (sim._gyroCal) {
      sim._gyroCal.push([sim.gyro.gx, sim.gyro.gy, sim.gyro.gz])
      if (sim._gyroCal.length >= 20) {
        var sx = 0, sy = 0, sz = 0
        for (var i = 0; i < sim._gyroCal.length; i++) {
          sx += sim._gyroCal[i][0]
          sy += sim._gyroCal[i][1]
          sz += sim._gyroCal[i][2]
        }
        var n = sim._gyroCal.length
        sim.profile.gyroBias = { x: sx / n, y: sy / n, z: sz / n }
        sim._gyroCal = null
        root.actionResult("Gyro calibrated for " + sim.modelLabel + " — drift offset stored")
      }
    }

    // 5. Polling rate benchmark ~500 Hz (2.0 ms interval with realistic micro-jitter)
    var sample = 2.0 + 0.12 * Math.sin(_simTick * 6.0)
    if (!sim._samples) sim._samples = []
    sim._samples.push(sample)
    if (sim._samples.length > 24) sim._samples.shift()
    var lat = GamepadModel.latencyMetrics(sim._samples)
    sim.avgMs = lat.avg
    sim.minMs = lat.min
    sim.maxMs = lat.max
    sim.jitter = lat.jitter
    sim.eps = lat.hz
    sim.pollingRate = lat.hz

    root.stats = computeStats()
    liveUpdated("sim0")
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

  // Set of device ids present in the most recent scan sweep. Used by
  // pruneDevices() to drop pads that vanished on replug/hot-unplug so
  // stale slots and bar figures clear out promptly.
  property var _seenThisScan: ({})

  Process {
    id: scanProc
    stdout: SplitParser {
      onRead: function (line) { root.ingestScanLine(line) }
    }
    onExited: {
      root.reconcileStreams()
      root.pruneDevices()
    }
  }

  function runScan() {
    if (scanProc.running) return
    root._seenThisScan = {}
    scanProc.command = ["bash", root.scanScript]
    scanProc.running = true
  }

  // Remove devices the last sweep no longer reported, releasing their
  // player slot and tearing down any still-running jstest/gyro streams.
  // sim0 (simulator bench) is deliberately left alone.
  function pruneDevices() {
    var next = {}
    var changed = false
    for (var id in _devices) {
      if (id === "sim0" || root._seenThisScan[String(id)]) {
        next[id] = _devices[id]
      } else {
        root.stopStream(id)
        root.stopGyroStream(id)
        root.releaseSlot(id)
        changed = true
      }
    }
    if (changed) {
      _devices = next
      root.stats = computeStats()
      devicesChanged()
    }
  }

  function ingestScanLine(line) {
    var raw = String(line || "").trim()
    if (raw.length === 0) return
    var rec
    try { rec = JSON.parse(raw) } catch (e) { return }
    if (!rec || !rec.id) return
    var id = String(rec.id)
    root._seenThisScan[id] = true
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
    if (id === "sim0") return
    if (!root.jstestAvailable) return
    if (!/^js\d+$/.test(String(id))) return
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
      if (id === "sim0") continue
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
    if (id === "sim0") return
    var d = device(id)
    if (!d || !d.motionNode || !/^event\d+$/.test(String(d.motionNode))) return
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
    var ax = Number(rec.ax) || 0
    var ay = Number(rec.ay) || 0
    var az = Number(rec.az) || 9.81
    var gx = Number(rec.gx) || 0
    var gy = Number(rec.gy) || 0
    var gz = Number(rec.gz) || 0
    var pitchRad = -Math.atan2(ay, Math.sqrt(ax * ax + az * az))
    var rollRad = Math.atan2(ax, az)
    var pitch = Math.max(-85, Math.min(85, pitchRad * 180 / Math.PI))
    var roll = Math.max(-180, Math.min(180, rollRad * 180 / Math.PI))
    var yaw = Math.max(-45, Math.min(45, gz * 25.0))

    d.gyro = {
      ax: ax, ay: ay, az: az,
      gx: gx, gy: gy, gz: gz,
      pitch: pitch,
      roll: roll,
      yaw: yaw,
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
          if (!d._samples) d._samples = []
          d._samples.push(delta)
          if (d._samples.length > 24) d._samples.shift()
          var metrics = GamepadModel.latencyMetrics(d._samples)
          d.avgMs = metrics.avg
          d.minMs = metrics.min
          d.maxMs = metrics.max
          d.jitter = metrics.jitter
          d.eps = metrics.hz
          d.pollingRate = metrics.hz
        }
      }
      d._lastTs = ts
      root.stats = computeStats()
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
    if (!d || !d.event || !/^event\d+$/.test(String(d.event))) {
      root.actionResult("No valid evdev node for " + id)
      return false
    }
    if (!root.evdevAvailable) {
      root.actionResult("python-evdev missing — sudo pacman -S --needed python-evdev")
      return false
    }
    var strength = d.profile && isFinite(Number(d.profile.rumble))
        ? Math.min(1.0, Math.max(0.1, Number(d.profile.rumble))) : 1.0
    var wVal = isFinite(Number(weak)) ? Number(weak) : 0.0
    var sVal = isFinite(Number(strong)) ? Number(strong) : 0.0
    var w = Math.round(Math.min(1.0, Math.max(0.0, wVal)) * strength * 65535)
    var s = Math.round(Math.min(1.0, Math.max(0.0, sVal)) * strength * 65535)
    var duration = Math.min(5000, Math.max(30, parseInt(ms, 10) || 500))
    return runAction(
      ["python3", root.rumbleScript, "/dev/input/" + d.event,
       String(w), String(s), String(duration)],
      "rumble")
  }

  // DualSense adaptive triggers: left/right in
  // off|weak|medium|strong|rigid|pulse|bow|machine gun.
  readonly property var allowedTriggerModes: [
    "off", "weak", "medium", "strong", "rigid", "pulse", "bow", "machine gun", "machinegun"
  ]

  function setTriggers(id, leftMode, rightMode, startPos, force) {
    var d = device(id)
    if (!d || d.layout !== "ps") {
      root.actionResult("Adaptive triggers need a DualSense pad")
      return false
    }
    var lm = String(leftMode || "").toLowerCase().trim()
    var rm = String(rightMode || "").toLowerCase().trim()
    if (allowedTriggerModes.indexOf(lm) === -1) lm = "off"
    if (allowedTriggerModes.indexOf(rm) === -1) rm = "off"

    var args = ["python3", root.triggersScript, "auto", lm, rm]
    if (startPos !== undefined && force !== undefined) {
      var sp = Math.min(1.0, Math.max(0.0, Number(startPos) || 0))
      var fc = Math.min(1.0, Math.max(0.0, Number(force) || 0))
      args.push(String(sp), String(fc))
    }
    return runAction(args, "triggers")
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

  Component.onCompleted: {
    envProc.running = true
    if (root.demoMode) root.startSimulator()
  }
  Component.onDestruction: {
    root.stopSimulator()
    for (var id in _streams) stopStream(id)
    for (var gid in _gyroStreams) stopGyroStream(gid)
  }
}
