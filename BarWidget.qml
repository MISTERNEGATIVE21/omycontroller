import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GamepadModel.js" as GamepadModel
import "."

// omycontroller — BarWidget.qml
//
// Status bar pill (plugin kind: bar-widget). Shows a mini controller
// silhouette, connection icon (GamePadla SVG / glyph), and battery percentage
// or simulator indicator. Reads manifest settings: showBatteryPercent,
// showLatency, lowBatteryThreshold, and pillStyle (badge, compact, iconOnly).
// Dynamic tooltip summarizes multi-pad slot status and latency.
// Toggles the Pro Control Deck panel on click.

BarWidget {
  id: root
  moduleName: "omycontroller"

  // ------------------------------------------------------------- service
  // Host bar hands third-party widgets a scoped shell facade; this
  // plugin's own service is looked up via "omycontroller".
  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("omycontroller") : null
  readonly property var pads: svc ? svc.deviceList : []

  // Lowest battery across pads drives the pill figure; charging pads count
  // as healthy so a docked pad never paints the bar urgent.
  readonly property var worstPad: {
    var worst = null
    for (var i = 0; i < pads.length; i++) {
      var p = pads[i]
      if (p.percent < 0 || p.charging) continue
      if (!worst || p.percent < worst.percent) worst = p
    }
    return worst
  }

  // Display pad for battery reporting
  readonly property var batteryPad: {
    if (worstPad) return worstPad
    for (var i = 0; i < pads.length; i++) {
      if (pads[i].percent >= 0) return pads[i]
    }
    return null
  }

  // Active pad for silhouette and connection icon
  readonly property var activePad: worstPad ? worstPad : (pads.length > 0 ? pads[0] : null)

  // ------------------------------------------------------------ settings
  readonly property bool showBatteryPercent: {
    var v = setting("showBatteryPercent", true)
    return v !== undefined && v !== null ? (v === true || v === "true") : true
  }
  readonly property bool showLatency: {
    var v = setting("showLatency", true)
    return v !== undefined && v !== null ? (v === true || v === "true") : true
  }
  readonly property int threshold: {
    var v = setting("lowBatteryThreshold", 15)
    var n = Number(v)
    return isFinite(n) ? n : 15
  }
  readonly property string pillStyle: {
    var v = setting("pillStyle", "badge")
    return v ? String(v).toLowerCase() : "badge"
  }

  readonly property color pillText: bar ? bar.barForeground : Color.foreground
  readonly property color batteryColor: !batteryPad ? pillText
    : (!batteryPad.charging && batteryPad.percent <= threshold) ? Color.urgent
    : (!batteryPad.charging && batteryPad.percent <= 35) ? Color.accent
    : pillText

  // Dynamic tooltip with multi-pad status and latency
  readonly property string tooltip: {
    if (pads.length === 0) return "omycontroller — no gamepads\nClick to open panel"
    var lines = []
    lines.push("omycontroller — " + pads.length + (pads.length === 1 ? " gamepad connected" : " gamepads connected"))
    for (var i = 0; i < pads.length; i++) {
      var p = pads[i]
      var slotName = "P" + (p.slot || (i + 1))
      var name = p.modelLabel || p.name || "Gamepad"
      var parts = [slotName, name]
      parts.push(GamepadModel.batteryLabel(p.percent, p.charging))
      if (p.connection) parts.push(p.connection)
      if (root.showLatency && p.avgMs > 0) {
        parts.push(GamepadModel.latencyLabel(p.avgMs, p.eps))
      }
      lines.push(parts.join(" · "))
    }
    lines.push("Click to toggle omycontroller deck")
    return lines.join("\n")
  }

  // ------------------------------------------------- panel lifecycle
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item && typeof panelLoader.item.open === "function") {
      panelLoader.item.open()
    }
  }

  function close() {
    if (panelLoader.item && typeof panelLoader.item.close === "function") {
      panelLoader.item.close()
    }
  }

  function toggle() {
    if (panelLoader.item && typeof panelLoader.item.toggle === "function") {
      panelLoader.item.toggle()
    } else if (root.opened) {
      root.close()
    } else if (panelLoader.item && typeof panelLoader.item.open === "function") {
      panelLoader.item.open()
    } else if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-shell shell toggle omycontroller '{}'")
    }
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function") {
      panelLoader.item.closeForPopoutSwitch()
    }
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  IpcHandler {
    target: "omycontroller"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }

    function playMelody(track: string, volume: real) {
      if (root.svc && typeof root.svc.playMelody === "function") {
        root.svc.playMelody("js0", track || "mario", volume !== undefined ? volume : 1.0)
      }
    }
    function stopMelody() {
      if (root.svc && typeof root.svc.stopMelody === "function") {
        root.svc.stopMelody()
      }
    }
    function probeAudio() {
      if (root.svc && typeof root.svc.probeAudio === "function") {
        root.svc.probeAudio()
      }
    }
    function playAudioTone(channel: string, sink: string) {
      if (root.svc && typeof root.svc.playAudioTone === "function") {
        root.svc.playAudioTone(channel, sink)
      }
    }
  }



  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    keepSpace: true
    fixedWidth: contentRow.implicitWidth + (root.pillStyle === "compact" ? Style.space(8) : Style.space(14))
    tooltipText: root.tooltip
    onPressed: function (b) {
      if (b === Qt.RightButton) {
        if (root.svc && typeof root.svc.rescan === "function") root.svc.rescan()
      } else {
        root.toggle()
      }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(4)
      // Plugin tray / bar SVG icon (always visible)
      Image {
        id: pluginIcon
        anchors.verticalCenter: parent.verticalCenter
        width: root.pillStyle === "compact" ? Style.space(14) : Style.space(16)
        height: root.pillStyle === "compact" ? Style.space(14) : Style.space(16)
        sourceSize.width: width
        sourceSize.height: height
        source: Qt.resolvedUrl("assets/tray_icon.svg")
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        rotation: (root.activePad && root.activePad.gyro) ? Math.max(-30, Math.min(30, (root.activePad.gyro.roll || 0) * 0.5)) : 0
        Behavior on rotation {
          SpringAnimation { spring: 3.5; damping: 0.35; epsilon: 0.1 }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: root.activePad
            ? GamepadModel.playerColor(root.activePad.slot, Color)
            : root.pillText
        }
      }

      // Idle state keeps clean icon-only presentation to prevent taskbar text clipping

      Item {
        id: connItem
        visible: root.activePad !== null
        anchors.verticalCenter: parent.verticalCenter
        width: root.pillStyle === "compact" ? 12 : 14
        height: root.pillStyle === "compact" ? 12 : 14
        implicitWidth: width
        implicitHeight: height

        Image {
          id: connSvg
          anchors.fill: parent
          sourceSize.width: width
          sourceSize.height: height
          source: root.activePad ? Qt.resolvedUrl(GamepadModel.connectionIcon(root.activePad.bus, root.activePad.phys)) : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          layer.enabled: true
          layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.pillText
          }
          visible: source !== ""
        }

        Text {
          anchors.centerIn: parent
          visible: !connSvg.visible || connSvg.status !== Image.Ready
          text: {
            if (!root.activePad) return ""
            var c = String(root.activePad.connection || "")
            if (c.indexOf("Bluetooth") !== -1) return "󰂯"
            if (c.indexOf("Dongle") !== -1) return "󰍹"
            return "󰌘"
          }
          color: root.pillText
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        id: batteryBadge
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pillStyle === "badge" && root.batteryPad !== null && root.showBatteryPercent
        height: Math.min(Style.space(18), (root.barSize || 30) - Style.space(6))
        width: batteryBadgeText.implicitWidth + Style.space(8)
        radius: Math.max(4, Style.cornerRadius)
        color: root.batteryPad && !root.batteryPad.charging && root.batteryPad.percent <= root.threshold
          ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.22)
          : (root.batteryPad && !root.batteryPad.charging && root.batteryPad.percent <= 35
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20)
              : Qt.rgba(root.pillText.r, root.pillText.g, root.pillText.b, 0.12))
        border.width: 1
        border.color: root.batteryPad && !root.batteryPad.charging && root.batteryPad.percent <= root.threshold
          ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.45)
          : (root.batteryPad && !root.batteryPad.charging && root.batteryPad.percent <= 35
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.40)
              : Qt.rgba(root.pillText.r, root.pillText.g, root.pillText.b, 0.18))

        Text {
          id: batteryBadgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.batteryPad ? GamepadModel.batteryLabel(root.batteryPad.percent, root.batteryPad.charging) : ""
          color: root.batteryColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          Behavior on color {
            enabled: !root.bar || root.bar.foregroundAnimationEnabled
            ColorAnimation { duration: 160 }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pillStyle === "compact" && root.batteryPad !== null && root.showBatteryPercent
        textFormat: Text.PlainText
        text: root.batteryPad ? GamepadModel.batteryLabel(root.batteryPad.percent, root.batteryPad.charging) : ""
        color: root.batteryColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }
}
