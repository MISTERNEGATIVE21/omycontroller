import QtQuick
import QtQuick.Effects
import Quickshell
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

  // Demo / simulator active status
  readonly property bool isDemo: (svc && (svc.demoMode || svc.simulatorActive))
    || (worstPad && worstPad.driverNote === "simulated")
    || (activePad && activePad.driverNote === "simulated")

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
    if (pads.length === 0 && !isDemo) return "omycontroller — no gamepads\nClick to open panel"
    var lines = []
    if (isDemo) {
      lines.push("⚡ omycontroller — Simulator Mode Active")
    } else {
      lines.push("omycontroller — " + pads.length + (pads.length === 1 ? " gamepad connected" : " gamepads connected"))
    }
    for (var i = 0; i < pads.length; i++) {
      var p = pads[i]
      var slotName = "P" + (p.slot || (i + 1))
      var name = p.modelLabel || p.name || "Gamepad"
      var parts = [slotName, name]
      if (p.driverNote === "simulated") parts.push("[Demo]")
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
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleDemo() {
    if (panelLoader.item && panelLoader.item.toggleDemo) panelLoader.item.toggleDemo()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
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
    keepSpace: true
    fixedWidth: contentRow.implicitWidth + (root.pillStyle === "compact" ? Style.space(8) : Style.space(14))
    tooltipText: root.tooltip
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: root.pillStyle === "compact" ? Style.space(4) : Style.space(6)

      ControllerArt {
        id: miniArt
        mini: true
        visible: root.pillStyle !== "iconOnly"
        layout: root.activePad ? (root.activePad.layout || "generic") : "generic"
        playerColor: root.activePad
          ? GamepadModel.playerColor(root.activePad.slot, Color)
          : Qt.rgba(root.pillText.r, root.pillText.g, root.pillText.b, 0.55)
        implicitWidth: root.pillStyle === "compact" ? 24 : 28
        implicitHeight: root.pillStyle === "compact" ? 14 : 16
        scale: root.pillStyle === "compact" ? 0.75 : 0.85
        anchors.verticalCenter: parent.verticalCenter
      }

      // Plugin icon glyph used by the iconOnly pill style.
      Image {
        id: pluginIcon
        visible: root.pillStyle === "iconOnly"
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        source: Qt.resolvedUrl("assets/icon.svg")
        fillMode: Image.PreserveAspectFit
        mipmap: true
        layer.enabled: visible
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: root.activePad
            ? GamepadModel.playerColor(root.activePad.slot, Color)
            : root.pillText
        }
      }

      Item {
        id: connItem
        visible: root.activePad !== null
        anchors.verticalCenter: parent.verticalCenter
        width: root.pillStyle === "compact" ? 12 : 14
        height: root.pillStyle === "compact" ? 12 : 14

        Image {
          id: connSvg
          anchors.fill: parent
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
        id: demoBadge
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pillStyle === "badge" && root.isDemo
        height: Math.min(Style.space(18), (root.barSize || 30) - Style.space(6))
        width: demoBadgeText.implicitWidth + Style.space(8)
        radius: Math.max(4, Style.cornerRadius)
        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.20)
        border.width: 1
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.40)

        Text {
          id: demoBadgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "⚡ DEMO"
          color: Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pillStyle === "compact" && root.isDemo
        textFormat: Text.PlainText
        text: "⚡"
        color: Color.accent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Rectangle {
        id: batteryBadge
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pillStyle === "badge" && !root.isDemo && root.batteryPad !== null && root.showBatteryPercent
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
        visible: root.pillStyle === "compact" && !root.isDemo && root.batteryPad !== null && root.showBatteryPercent
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

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.pads.length === 0 && !root.isDemo && root.pillStyle !== "iconOnly"
        textFormat: Text.PlainText
        text: "—"
        color: Qt.rgba(root.pillText.r, root.pillText.g, root.pillText.b, 0.45)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
