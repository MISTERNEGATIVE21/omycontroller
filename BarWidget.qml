import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "GamepadModel.js" as GamepadModel
import "."

// Quatro — BarWidget.qml
//
// Bar pill (plugin kind: bar-widget). Shows a mini controller glyph plus
// the most urgent battery figure across all connected pads, and toggles
// the popout panel on click. The Quattro shell routes IPC summon/hide/
// toggle for this plugin id to open()/close()/toggle() here — that is how
// the SUPER+G keybind and the fuzzel desktop entry open the panel without
// any extra process.

BarWidget {
  id: root
  moduleName: "quatro.gamepad"

  // ------------------------------------------------------------- service
  // The built-in bar hands third-party widgets a scoped shell facade; this
  // plugin's own service is the one id it is allowed to look up.
  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("quatro.gamepad") : null
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
  readonly property int threshold: {
    var v = setting("lowBatteryThreshold", 15)
    var n = Number(v)
    return isFinite(n) ? n : 15
  }
  readonly property color pillText: bar ? bar.barForeground : Color.foreground
  readonly property color batteryColor: !worstPad ? pillText
    : worstPad.percent <= threshold ? Color.urgent
    : worstPad.percent <= 35 ? Color.accent
    : pillText

  readonly property string tooltip: {
    if (pads.length === 0) return "Quatro — no gamepads"
    var lines = []
    for (var i = 0; i < pads.length; i++) {
      var p = pads[i]
      var parts = ["P" + (p.slot || 1), p.modelLabel,
                   GamepadModel.batteryLabel(p.percent, p.charging),
                   p.connection]
      if (setting("showLatency", true) && p.avgMs > 0)
        parts.push(GamepadModel.latencyLabel(p.avgMs, p.eps))
      lines.push(parts.join(" · "))
    }
    lines.push("Click to open the Quatro panel")
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
    fixedWidth: contentRow.implicitWidth + Style.space(14)
    tooltipText: root.tooltip
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      ControllerArt {
        mini: true
        playerColor: root.pads.length > 0 ? GamepadModel.playerColor(root.pads[0].slot, Color) : Qt.rgba(root.pillText.r, root.pillText.g, root.pillText.b, 0.55)
        implicitWidth: 30
        implicitHeight: 16
        scale: 0.9
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.worstPad !== null
        textFormat: Text.PlainText
        text: root.worstPad ? GamepadModel.batteryLabel(root.worstPad.percent, root.worstPad.charging) : ""
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
        visible: root.pads.length === 0
        textFormat: Text.PlainText
        text: "—"
        color: Qt.rgba(root.pillText.r, root.pillText.g, root.pillText.b, 0.45)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
