import QtQuick
import Quickshell
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
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null

  // ------------------------------------------------------------ service
  readonly property var svc: {
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

  Connections {
    target: svc
    function onLiveUpdated(id) {
      if (id === root.selectedId) root.refreshLive()
    }
    function onDevicesChanged() {
      if (!root.sel && root.pads.length > 0) root.select(root.pads[0].id)
      if (root.sel) root.refreshLive()
    }
    function onActionResult(message) {
      root.actionMsg = String(message || "")
    }
  }

  onSelChanged: root.refreshLive()
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
  readonly property var tabNames: ["Overview", "Sticks & Triggers", "Haptics", "Motion", "Device Specs"]

  // ------------------------------------------------------------ actions & tuning
  property string actionMsg: ""
  property real lfMixer: 0.70
  property real hfMixer: 0.50
  property string selectedTriggerMode: "Rigid"
  property real triggerStartPos: 0.15
  property real triggerForce: 0.85

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
        { w: 0.6, s: 0.8, d: 160 }
      ]
    } else if (patternName === "heartbeat") {
      rhythmSteps = [
        { w: 0.7, s: 0.4, d: 100 },
        { w: 0.0, s: 0.0, d: 120 },
        { w: 0.9, s: 0.8, d: 220 }
      ]
    } else if (patternName === "ramp") {
      rhythmSteps = [
        { w: 0.25, s: 0.3, d: 140 },
        { w: 0.55, s: 0.6, d: 140 },
        { w: 1.0,  s: 1.0, d: 240 }
      ]
    } else if (patternName === "burst") {
      rhythmSteps = [
        { w: 1.0, s: 1.0, d: 600 }
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
    if (root.sel.id === "sim0") {
      root.actionMsg = "Rumble simulated (" + Math.round(w * 100) + "% HF / " + Math.round(s * 100) + "% LF) on " + root.sel.modelLabel
      return
    }
    root.svc.rumble(root.sel.id, w, s, ms)
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

  function stickX(side) {
    if (!root.sel) return 0
    var axes = root.liveAxes
    var axisMap = GamepadModel.axesMap(root.sel.layout, axes ? axes.length : 0, root.sel.axisNames)
    var idx = side === "l" ? axisMap.lx : axisMap.rx
    if (idx === -1 || !axes || idx >= axes.length) return 0
    var v = Number(axes[idx])
    return isFinite(v) ? v : 0
  }

  function stickY(side) {
    if (!root.sel) return 0
    var axes = root.liveAxes
    var axisMap = GamepadModel.axesMap(root.sel.layout, axes ? axes.length : 0, root.sel.axisNames)
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
    if (!root.sel) return 0
    var axes = root.liveAxes
    var axisMap = GamepadModel.axesMap(root.sel.layout, axes ? axes.length : 0, root.sel.axisNames)
    var tables = GamepadModel.buttonTables(root.sel.layout)
    var idx = side === "l" ? axisMap.lt : axisMap.rt
    var btnPressed = side === "l"
      ? !!(root.liveButtons && root.liveButtons[tables.triggerL])
      : !!(root.liveButtons && root.liveButtons[tables.triggerR])
    var fallback = btnPressed ? 1 : 0
    var raw = (idx !== -1 && axes && idx < axes.length && isFinite(Number(axes[idx]))) ? Number(axes[idx]) : fallback
    return GamepadModel.triggerNorm(root.sel.layout, raw)
  }

  // ------------------------------------------------------------ lifecycle
  function open() { root.controller.show() }
  function close() { root.controller.hide() }
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

          // Right Controls: Rescan Hardware Button
          Row {
            id: headerRightRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

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
              width: Style.space(280)
              height: Style.space(170)
              showLabels: true
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No Gamepads Detected"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            width: parent.width - Style.space(40)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: "Plug in an Xbox, PlayStation, Switch Pro, or generic controller via USB cable, Bluetooth, or wireless adapter. Up to 4 players supported with real-time diagnostics, circularity radar, haptics, and 6-DOF gyro."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "↻ Rescan Hardware"
            focusable: true
            foreground: root.barForeground
            accent: Color.accent
            onClicked: if (root.svc) root.svc.runScan()
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
                      playerColor: slotPill.slotColor
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
                    { name: "Sticks & Triggers", icon: "🕹" },
                    { name: "Haptics", icon: "📳" },
                    { name: "Motion", icon: "🧭" },
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
                    anchors.horizontalCenter: parent.horizontalCenter
                    layout: root.sel ? root.sel.layout : "generic"
                    playerColor: root.playerColor
                    buttons: root.liveButtons
                    axes: root.liveAxes
                    axisNames: root.sel && root.sel.axisNames ? root.sel.axisNames : []
                    profile: root.sel && root.sel.profile ? root.sel.profile : null
                    gyro: root.liveGyro
                    width: Style.space(310)
                    height: Style.space(190)
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

                      Text {
                        text: "Live Button Map (Active Physical Press Highlight)"
                        color: Qt.darker(root.barForeground, 1.4)
                        font.family: Style.font.family
                        font.pixelSize: 8
                        font.bold: true
                      }

                      // 4 face buttons
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? root.sel.layout : "generic", root.sel ? root.sel.profile : null)

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "South / Bottom"
                          label: root.sel && root.sel.layout === "ps" ? "×" : (root.sel && root.sel.profile && root.sel.profile.remapPreset === "nintendo_swap" ? "B" : "A")
                          btnIdx: parent.t.faceBottom
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceBottom]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "East / Right"
                          label: root.sel && root.sel.layout === "ps" ? "○" : (root.sel && root.sel.profile && root.sel.profile.remapPreset === "nintendo_swap" ? "A" : "B")
                          btnIdx: parent.t.faceRight
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceRight]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "West / Left"
                          label: root.sel && root.sel.layout === "ps" ? "□" : (root.sel && root.sel.profile && root.sel.profile.remapPreset === "nintendo_swap" ? "Y" : "X")
                          btnIdx: parent.t.faceLeft
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceLeft]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "North / Top"
                          label: root.sel && root.sel.layout === "ps" ? "△" : (root.sel && root.sel.profile && root.sel.profile.remapPreset === "nintendo_swap" ? "X" : "Y")
                          btnIdx: parent.t.faceTop
                          active: root.liveButtons && !!root.liveButtons[parent.t.faceTop]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }
                      }

                      // Shoulder and stick click buttons
                      Row {
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property var t: GamepadModel.buttonTables(root.sel ? root.sel.layout : "generic", root.sel ? root.sel.profile : null)

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "Left Shoulder"
                          label: root.sel && root.sel.layout === "ps" ? "L1" : "LB"
                          btnIdx: parent.t.bumperL
                          active: root.liveButtons && !!root.liveButtons[parent.t.bumperL]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "Right Shoulder"
                          label: root.sel && root.sel.layout === "ps" ? "R1" : "RB"
                          btnIdx: parent.t.bumperR
                          active: root.liveButtons && !!root.liveButtons[parent.t.bumperR]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "Left Stick Click"
                          label: "L3 / LS"
                          btnIdx: parent.t.stickL
                          active: root.liveButtons && !!root.liveButtons[parent.t.stickL]
                          accent: root.playerColor
                          foreground: root.barForeground
                        }

                        RemapPill {
                          width: (parent.width - 3 * Style.space(6)) / 4
                          role: "Right Stick Click"
                          label: "R3 / RS"
                          btnIdx: parent.t.stickR
                          active: root.liveButtons && !!root.liveButtons[parent.t.stickR]
                          accent: root.playerColor
                          foreground: root.barForeground
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

                  Button {
                    width: parent.width
                    text: "▶ Test Rumble Mix (0.5s)"
                    focusable: true
                    foreground: root.barForeground
                    accent: root.playerColor
                    onClicked: root.triggerRumble(root.hfMixer, root.lfMixer, 500)
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
                    height: Style.space(165)
                    radius: Math.max(4, Style.cornerRadius)
                    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
                    border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
                    border.width: 1
                    clip: true

                    ControllerArt {
                      anchors.centerIn: parent
                      layout: root.sel ? root.sel.layout : "generic"
                      playerColor: root.playerColor
                      buttons: root.liveButtons
                      axes: root.liveAxes
                      axisNames: root.sel && root.sel.axisNames ? root.sel.axisNames : []
                      profile: root.sel && root.sel.profile ? root.sel.profile : null
                      gyro: root.liveGyro
                      width: Style.space(250)
                      height: Style.space(150)
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

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      width: Style.space(190)
                      text: "⌖ Calibrate Zero Drift"
                      focusable: true
                      foreground: root.barForeground
                      accent: root.playerColor
                      onClicked: if (root.svc && root.sel) root.svc.calibrateGyro(root.sel.id)
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(198)
                      text: root.sel && root.sel.profile && root.sel.profile.gyroBias
                        ? "Drift bias stored: X=" + root.sel.profile.gyroBias.x.toFixed(1) + " Y=" + root.sel.profile.gyroBias.y.toFixed(1)
                        : "Uncalibrated bias"
                      color: Qt.darker(root.barForeground, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    width: parent.width
                    text: "Hold pad completely stationary on a flat surface while calibrating. Drift offsets persist across restarts."
                    color: Qt.darker(root.barForeground, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }

                // ---------------------------------------------------- TAB 4: DEVICE SPECS
                Column {
                  visible: root.currentTab === 4
                  width: parent.width
                  spacing: Style.space(6)

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
    property string label: ""
    property int btnIdx: -1
    property bool active: false
    property color accent: root.playerColor
    property color foreground: root.barForeground

    height: Style.space(40)
    radius: Math.max(3, Style.cornerRadius - 1)
    color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.28) : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
    border.color: active ? accent : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    border.width: active ? 1.5 : 1
    clip: true

    Behavior on color { ColorAnimation { duration: 40 } }

    Column {
      anchors.centerIn: parent
      spacing: 1

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: rp.label
        color: rp.active ? rp.accent : rp.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: rp.btnIdx >= 0 ? ("Btn " + rp.btnIdx) : "Axis"
        color: rp.active ? rp.accent : Qt.darker(rp.foreground, 1.6)
        font.family: Style.font.family
        font.pixelSize: 8
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
