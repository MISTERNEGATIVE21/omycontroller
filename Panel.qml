import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "GamepadModel.js" as GamepadModel
import "."

// Quatro — Panel.qml
//
// Popout control center, anchored to the bar pill (loaded by BarWidget.qml
// through a Loader — the same structure Omarchy's clock plugin uses; the
// panel is intentionally NOT a separate manifest kind).
//
// Sections:
//   1. Header + live pad count
//   2. P1–P4 device menu (click to select)
//   3. Selected pad: model-accurate live art + status chips
//      (protocol / mode, connection, latency, battery)
//   4. Rumble test (weak / strong / both)
//   5. DualSense adaptive triggers (off/weak/medium/strong/rigid/pulse)
//   6. Deadzone sliders (L/R stick, L/R trigger) with live preview rings
//
// All colors come from the shell theme singleton so Quatro follows every
// Omarchy theme, not just the default.

Panel {
  id: root
  moduleName: "quatro.gamepad"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // ------------------------------------------------------------ service
  readonly property var svc: {
    if (bar && bar.shell && typeof bar.shell.serviceFor === "function")
      return bar.shell.serviceFor("quatro.gamepad")
    return null
  }
  readonly property var pads: svc ? svc.deviceList : []

  // ------------------------------------------------------------ settings
  readonly property bool showLatency: hostWidget ? hostWidget.setting("showLatency", true) !== false : true
  readonly property int lowBatteryThreshold: {
    var v = hostWidget ? hostWidget.setting("lowBatteryThreshold", 15) : 15
    var n = Number(v)
    return isFinite(n) ? n : 15
  }

  // ------------------------------------------------------------ selection
  property string selectedId: ""
  readonly property var sel: {
    for (var i = 0; i < pads.length; i++)
      if (pads[i].id === selectedId) return pads[i]
    return pads.length > 0 ? pads[0] : null
  }
  readonly property color playerColor: sel ? GamepadModel.playerColor(sel.slot, Color) : Color.accent

  // Live state mirrors (copied on every event so bindings refresh; the
  // service mutates its state in place for performance).
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
    liveGyro = g ? { ax: g.ax, ay: g.ay, az: g.az, gx: g.gx, gy: g.gy, gz: g.gz, afs: g.afs, gfs: g.gfs } : null
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
  }

  onSelChanged: root.refreshLive()

  Component.onCompleted: if (pads.length > 0) selectedId = pads[0].id

  // ------------------------------------------------------------ actions
  property string actionMsg: ""
  Connections {
    target: svc
    function onActionResult(message) { root.actionMsg = String(message || "") }
  }

  // ------------------------------------------------------------ panel open/close
  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---------------------------------------------------- header
        Item {
          width: parent.width
          height: headerRow.implicitHeight

          Row {
            id: headerRow
            spacing: Style.space(8)

            Text {
              text: "QUATRO"
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
                text: root.pads.length === 0 ? "no pads" : root.pads.length + (root.pads.length === 1 ? " pad" : " pads")
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "quatro.gamepad"
            color: Qt.darker(root.barForeground, 1.6)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ---------------------------------------------------- empty state
        Column {
          visible: root.pads.length === 0
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: "No gamepads detected"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            width: parent.width
            text: root.svc && !root.svc.jstestAvailable
                  ? "Connect a controller. For the live tester install: pacman -S --needed linuxconsole"
                  : "Connect a controller — it will appear here as P1. Up to four pads supported."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------------------------------------------------- device menu
        Column {
          visible: root.pads.length > 0
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: 4

            delegate: Rectangle {
              id: slotRow
              required property int index
              readonly property var pad: root.pads.length > index ? root.pads[index] : null
              readonly property bool isSel: root.sel && pad && pad.id === root.sel.id
              readonly property color slotColor: GamepadModel.playerColor(index + 1, Color)

              width: parent.width
              height: Style.space(34)
              radius: Math.max(4, Style.cornerRadius)
              color: isSel ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.10)
                   : padMouse.containsMouse ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.05)
                   : "transparent"
              border.color: isSel ? slotColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
              border.width: isSel ? 1 : 0

              MouseArea {
                id: padMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.select(slotRow.pad ? slotRow.pad.id : "")
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 10; height: 10; radius: 5
                  color: slotRow.pad ? slotRow.slotColor : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.15)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "P" + (slotRow.index + 1)
                  color: slotRow.pad ? root.barForeground : Qt.darker(root.barForeground, 1.7)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(150)
                  elide: Text.ElideRight
                  text: slotRow.pad ? slotRow.pad.modelLabel : "empty slot"
                  color: slotRow.pad ? root.barForeground : Qt.darker(root.barForeground, 1.7)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Item { width: 1; height: 1 }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: slotRow.pad ? GamepadModel.batteryLabel(slotRow.pad.percent, slotRow.pad.charging) : ""
                  color: slotRow.pad ? GamepadModel.batteryText(root.barForeground, Color, slotRow.pad.percent, root.lowBatteryThreshold) : "transparent"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: slotRow.pad && slotRow.pad.percent >= 0 && slotRow.pad.percent <= root.lowBatteryThreshold
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: slotRow.pad ? GamepadModel.connectionShort(slotRow.pad.connection) : ""
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // ---------------------------------------------------- live art
        Column {
          visible: root.sel !== null
          width: parent.width
          spacing: Style.space(8)

          ControllerArt {
            anchors.horizontalCenter: parent.horizontalCenter
            layout: root.sel ? root.sel.layout : "generic"
            playerColor: root.playerColor
            buttons: root.liveButtons
            axes: root.liveAxes
            axisNames: root.sel && root.sel.axisNames ? root.sel.axisNames : []
            profile: root.sel && root.sel.profile ? root.sel.profile : null
            width: Style.space(282)
            height: Style.space(173)
            scale: 282 / 340
          }

          // status chips
          Grid {
            columns: 2
            width: parent.width
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(6)

            Chip {
              width: (parent.width - Style.space(8)) / 2
              label: "Mode / protocol"
              value: root.sel ? root.sel.protocol : "—"
              sub: root.sel ? (root.sel.maker !== "" ? root.sel.maker + " · " + root.sel.driverNote : root.sel.driverNote) : ""
              foreground: root.barForeground
            }
            Chip {
              width: (parent.width - Style.space(8)) / 2
              label: "Connection"
              value: root.sel ? root.sel.connection : "—"
              sub: root.sel ? ("/dev/input/" + root.sel.id) : ""
              foreground: root.barForeground
            }
            Chip {
              width: (parent.width - Style.space(8)) / 2
              label: "Input latency"
              value: root.showLatency && root.sel ? GamepadModel.latencyLabel(root.sel.avgMs, root.sel.eps) : "hidden"
              sub: root.sel && root.sel.live ? "live" : "press a button"
              foreground: root.barForeground
            }
            Chip {
              width: (parent.width - Style.space(8)) / 2
              label: "Battery"
              value: root.sel ? GamepadModel.batteryLabel(root.sel.percent, root.sel.charging) : "—"
              sub: root.sel && root.sel.percent >= 0 ? (root.sel.percent <= root.lowBatteryThreshold ? "low — charge soon" : "healthy") : "no battery data"
              valueColor: root.sel ? GamepadModel.batteryText(root.barForeground, Color, root.sel.percent, root.lowBatteryThreshold) : root.barForeground
              foreground: root.barForeground
            }
            Chip {
              width: (parent.width - Style.space(8)) / 2
              label: "Hardware"
              value: root.sel ? root.sel.axisCount + " axes · " + root.sel.buttonCount + " buttons" + (root.sel.motionNode ? " · gyro" : "") : "—"
              sub: root.sel ? GamepadModel.shapeLabel(root.sel.layout) : ""
              foreground: root.barForeground
            }
          }
        }

        // ---------------------------------------------------- feedback
        Column {
          visible: root.sel !== null
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Feedback — rumble & adaptive triggers"
            foreground: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Row {
            spacing: Style.space(6)

            Repeater {
              model: [
                { label: "Weak",   w: 0.35, s: 0.0 },
                { label: "Strong", w: 0.0,  s: 0.55 },
                { label: "Both 0.5s", w: 0.35, s: 0.55 }
              ]

              delegate: Button {
                required property var modelData
                text: modelData.label
                focusable: true
                enabled: root.svc && root.svc.evdevAvailable
                opacity: enabled ? 1 : 0.45
                foreground: root.barForeground
                accent: root.playerColor
                onClicked: root.svc.rumble(root.sel.id, modelData.w, modelData.s, 500)
              }
            }
          }

          DeadzoneSlider {
            width: parent.width
            labelText: "Rumble power"
            maxValue: 1
            value: root.sel && root.sel.profile && isFinite(Number(root.sel.profile.rumble)) ? Number(root.sel.profile.rumble) : 1
            foreground: root.barForeground
            accent: root.playerColor
            onMoved: function (v) { if (root.svc && root.sel) root.svc.setRumble(root.sel.id, Math.round(v * 100) / 100) }
          }

          Text {
            visible: root.svc && !root.svc.evdevAvailable
            width: parent.width
            text: "Rumble needs python-evdev: pacman -S --needed python-evdev"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            visible: root.svc && root.svc.hasDualSense
            spacing: Style.space(8)

            Dropdown {
              id: trigLeftDrop
              width: Style.space(150)
              label: "L2 triggers"
              value: "off"
              options: root.triggerModes
              foreground: root.barForeground
              onChanged: function (v) { root.svc.setTriggers(root.sel ? root.sel.id : "", v, trigRightDrop.value) }
            }

            Dropdown {
              id: trigRightDrop
              width: Style.space(150)
              label: "R2 triggers"
              value: "off"
              options: root.triggerModes
              foreground: root.barForeground
              onChanged: function (v) { root.svc.setTriggers(root.sel ? root.sel.id : "", trigLeftDrop.value, v) }
            }
          }

          Text {
            visible: root.svc && root.svc.hasDualSense
            width: parent.width
            text: "DualSense adaptive triggers via hidraw — wired (USB) recommended."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------------------------------------------------- deadzones
        Column {
          visible: root.sel !== null
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Deadzones"
            foreground: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
          }

          DeadzoneSlider {
            width: parent.width
            labelText: "Left stick"
            value: root.sel && root.sel.profile ? root.sel.profile.stickL : 0.1
            foreground: root.barForeground
            accent: root.playerColor
            onMoved: function (v) { root.setDz("stickL", v) }
          }
          DeadzoneSlider {
            width: parent.width
            labelText: "Right stick"
            value: root.sel && root.sel.profile ? root.sel.profile.stickR : 0.1
            foreground: root.barForeground
            accent: root.playerColor
            onMoved: function (v) { root.setDz("stickR", v) }
          }
          DeadzoneSlider {
            width: parent.width
            labelText: "Left trigger"
            value: root.sel && root.sel.profile ? root.sel.profile.trigL : 0.05
            foreground: root.barForeground
            accent: root.playerColor
            onMoved: function (v) { root.setDz("trigL", v) }
          }
          DeadzoneSlider {
            width: parent.width
            labelText: "Right trigger"
            value: root.sel && root.sel.profile ? root.sel.profile.trigR : 0.05
            foreground: root.barForeground
            accent: root.playerColor
            onMoved: function (v) { root.setDz("trigR", v) }
          }

          Text {
            width: parent.width
            text: "Profiles are stored per pad and survive replug. Rings on the sticks preview the cutoff; with xpadneo the kernel applies stick zones natively."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------------------------------------------------- motion (gyro)
        Column {
          visible: root.sel !== null && root.sel.motionNode !== undefined && root.sel.motionNode !== ""
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "Motion — gyro & accelerometer"
            foreground: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Row {
            spacing: Style.space(10)

            GyroView {
              width: Style.space(118)
              height: Style.space(118)
              gyro: root.liveGyro
              bias: root.sel && root.sel.profile && root.sel.profile.gyroBias ? root.sel.profile.gyroBias : null
              accent: root.playerColor
              foreground: root.barForeground
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Text {
                width: Style.space(190)
                elide: Text.ElideRight
                text: root.liveGyro
                      ? "gyro " + Math.round((root.liveGyro.gx || 0) * 100) + "% · " + Math.round((root.liveGyro.gy || 0) * 100) + "%"
                      : "gyro idle"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                width: Style.space(190)
                elide: Text.ElideRight
                text: root.sel && root.sel.profile && root.sel.profile.gyroBias
                      ? "drift offset stored"
                      : "drift: uncalibrated"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                width: Style.space(190)
                elide: Text.ElideRight
                text: root.liveGyro ? "accel z " + Math.round((root.liveGyro.az || 0) * 100) + "%" : "shake the pad — dots move"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
              Button {
                text: "Calibrate (hold still)"
                focusable: true
                enabled: root.svc && root.sel
                foreground: root.barForeground
                accent: root.playerColor
                onClicked: root.svc.calibrateGyro(root.sel.id)
              }
            }
          }

          Text {
            width: parent.width
            text: "Motion is read straight from the pad's sensor node — DualSense, DualShock 4, Switch Pro and Joy-Cons expose gyro. No extra package needed."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------------------------------------------------- footer
        Text {
          width: parent.width
          text: root.actionMsg !== "" ? root.actionMsg : (root.svc && root.svc.jstestAvailable ? "Scan " + (root.svc.scanIntervalMs / 1000) + "s · jstest live input" : "Scan " + (root.svc ? root.svc.scanIntervalMs / 1000 : 2) + "s · live input needs linuxconsole (jstest)")
          color: Qt.darker(root.barForeground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  readonly property var triggerModes: [
    { value: "off", label: "Off" },
    { value: "weak", label: "Weak" },
    { value: "medium", label: "Medium" },
    { value: "strong", label: "Strong" },
    { value: "rigid", label: "Rigid" },
    { value: "pulse", label: "Pulse" }
  ]

  function setDz(key, value) {
    if (!root.sel || !root.svc) return
    root.svc.setDeadzone(root.sel.id, key, value)
    root.refreshLive()
  }

  // ============================================================ components
  component Chip : Rectangle {
    id: chip
    property string label: ""
    property string value: ""
    property string sub: ""
    property color valueColor: chip.foreground
    property color foreground: Color.foreground

    height: chipCol.implicitHeight + Style.space(12)
    radius: Math.max(4, Style.cornerRadius)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    border.width: 1

    Column {
      id: chipCol
      anchors.centerIn: parent
      width: parent.width - Style.space(12)
      spacing: 1

      Text {
        width: parent.width
        text: chip.label
        color: Qt.darker(chip.foreground, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: chip.value
        color: chip.valueColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
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

  component DeadzoneSlider : Row {
    id: dzRow
    property string labelText: ""
    property real value: 0
    property real maxValue: 0.5
    property color foreground: Color.foreground
    property color accent: Color.accent
    signal moved(real v)

    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(74)
      text: dzRow.labelText
      color: dzRow.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    PanelSlider {
      id: slider
      width: parent.width - Style.space(96)
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: dzRow.maxValue
      step: 0.01
      value: dzRow.value
      fillColor: dzRow.accent
      knobColor: dzRow.accent
      trackColor: Qt.rgba(dzRow.foreground.r, dzRow.foreground.g, dzRow.foreground.b, 0.18)
      onMoved: function (v) { dzRow.moved(Math.round(v * 100) / 100) }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36)
      text: Math.round(dzRow.value * 100) + "%"
      color: Qt.darker(dzRow.foreground, 1.3)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
    }
  }

  // Live motion gauge: accent bubble = gyro rotation rate (drift-corrected
  // when a bias has been stored), faint dot = accelerometer tilt vector.
  component GyroView : Rectangle {
    id: gv
    property var gyro: null
    property var bias: null
    property color accent: Color.accent
    property color foreground: Color.foreground

    function cv(v) {
      var n = Number(v)
      return isFinite(n) ? Math.max(-1, Math.min(1, n)) : 0
    }

    readonly property real r: (Math.min(width, height) - Style.space(26)) / 2
    readonly property real gxd: cv(gyro ? (gyro.gx || 0) - (bias ? bias.x : 0) : 0)
    readonly property real gyd: cv(gyro ? (gyro.gy || 0) - (bias ? bias.y : 0) : 0)
    readonly property real axd: cv(gyro ? gyro.ax || 0 : 0)
    readonly property real ayd: cv(gyro ? gyro.ay || 0 : 0)

    radius: Math.max(4, Style.cornerRadius)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    border.width: 1

    Text {
      visible: !gv.gyro
      anchors.centerIn: parent
      text: "waiting for\nmotion data…"
      horizontalAlignment: Text.AlignHCenter
      color: Qt.darker(gv.foreground, 1.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      visible: gv.gyro !== null
      anchors.centerIn: parent
      width: gv.r * 2; height: width; radius: gv.r
      color: "transparent"
      border.color: Qt.rgba(gv.foreground.r, gv.foreground.g, gv.foreground.b, 0.18)
      border.width: 1
    }
    Rectangle {
      visible: gv.gyro !== null
      anchors.centerIn: parent
      width: gv.r; height: width; radius: gv.r / 2
      color: "transparent"
      border.color: Qt.rgba(gv.foreground.r, gv.foreground.g, gv.foreground.b, 0.10)
      border.width: 1
    }

    // accelerometer tilt dot (faint)
    Rectangle {
      visible: gv.gyro !== null
      width: 8; height: 8; radius: 4
      x: gv.width / 2 + gv.axd * gv.r * 0.8 - 4
      y: gv.height / 2 + gv.ayd * gv.r * 0.8 - 4
      color: Qt.rgba(gv.foreground.r, gv.foreground.g, gv.foreground.b, 0.35)
      Behavior on x { NumberAnimation { duration: 60 } }
      Behavior on y { NumberAnimation { duration: 60 } }
    }

    // gyro rate bubble (accent)
    Rectangle {
      visible: gv.gyro !== null
      width: 12; height: 12; radius: 6
      x: gv.width / 2 + gv.gxd * gv.r - 6
      y: gv.height / 2 + gv.gyd * gv.r - 6
      color: gv.accent
      Behavior on x { NumberAnimation { duration: 60 } }
      Behavior on y { NumberAnimation { duration: 60 } }
    }

    Text {
      visible: gv.gyro !== null
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(3)
      text: gv.gyro && gv.gyro.gfs ? "gyro full scale ±" + gv.gyro.gfs : "gyro"
      color: Qt.darker(gv.foreground, 1.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
