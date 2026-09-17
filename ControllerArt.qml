import QtQuick
import qs.Commons
import "GamepadModel.js" as GamepadModel

// Quatro — ControllerArt.qml
//
// Theme-aware, model-accurate controller rendering built from QML
// primitives (no SVG plugin, no external assets — hot-reloads cleanly and
// repaints instantly at input rate). Four layouts:
//
//   xbox     A/B/X/Y, asymmetric sticks, view/menu/guide
//   ps       ×/○/□/△, symmetric sticks, create/options, touchpad, PS logo
//   switch   Nintendo glyph order (A right, B bottom), +/-, home, capture
//   generic  neutral 1..4 diamond
//
// Live behavior:
//   - face buttons / bumpers / dpad / center keys light up in playerColor
//   - sticks draw raw dot (faint) + deadzone-corrected dot (solid)
//   - triggers are vertical fill bars driven by their analog axis
//   - a dashed inner ring on each stick shows the stored deadzone
//
// Input tables follow the common kernel driver button order (xpad/xpadneo,
// hid-playstation, hid-nintendo). Pads that deviate still light the body
// outline when an unmapped index fires, so nothing ever looks frozen.

Item {
  id: root

  property string layout: "generic"      // xbox | ps | switch | generic
  property color playerColor: Color.accent
  property var buttons: ({})             // js button index -> bool
  property var axes: []                  // normalized -1..1
  property var profile: ({})             // deadzone profile (stickL/stickR/...)
  property bool mini: false              // tiny silhouette for menu rows
  property bool showLabels: true

  implicitWidth: mini ? 34 : 340 * scale
  implicitHeight: mini ? 20 : 208 * scale

  property real scale: 1.0
  readonly property bool isPs: layout === "ps"
  readonly property bool isSwitch: layout === "switch"
  readonly property bool isXbox: layout === "xbox"

  // ---------------------------------------------------------------- tables
  readonly property var tables: GamepadModel.buttonTables(layout)
  readonly property var axisMap: GamepadModel.axesMap(layout, axes ? axes.length : 0)

  function pressed(idx) { return !!(buttons && buttons[idx]) }
  function axisValue(idx, fallback) {
    if (idx === -1) return fallback
    if (!axes || idx >= axes.length) return fallback
    var v = Number(axes[idx])
    return isFinite(v) ? v : fallback
  }
  function triggerNorm(side) {
    var raw = axisValue(side === "l" ? axisMap.lt : axisMap.rt, side === "l" ? pressed(tables.triggerL) ? 1 : 0 : pressed(tables.triggerR) ? 1 : 0)
    return GamepadModel.triggerNorm(layout, raw)
  }
  function stickX(side) { return axisValue(side === "l" ? axisMap.lx : axisMap.rx, 0) }
  function stickY(side) { return axisValue(side === "l" ? axisMap.ly : axisMap.ry, 0) }
  function dzFor(side) {
    var p = profile || {}
    var v = Number(side === "l" ? p.stickL : p.stickR)
    return isFinite(v) ? v : 0.1
  }

  // Any pressed button that no art element claims lights the outline —
  // guarantees visible feedback for unusual pads.
  readonly property bool unknownPress: {
    if (!buttons) return false
    for (var idx in buttons) {
      if (!buttons[idx]) continue
      var n = parseInt(idx, 10)
      if (tables.known.indexOf(n) === -1) return true
    }
    return false
  }

  // -------------------------------------------------------------- palette
  readonly property color bodyColor: Color.popups.background
  readonly property color bodyBorder: unknownPress
    ? playerColor
    : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.35)
  readonly property color glyphColor: Color.popups.text
  readonly property color dimGlyph: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.55)
  readonly property color idleFill: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.10)

  // ------------------------------------------------------------- geometry
  // Per-layout element centers inside the 340x208 canvas. Xbox is
  // asymmetric (left stick high, dpad low), PS/Switch follow their real
  // silhouettes.
  readonly property var geo: {
    if (isXbox) return { stickL: [100, 112], stickR: [212, 140], dpad: [138, 128], face: [240, 108], bumpers: [42, 252] }
    if (isPs) return { stickL: [134, 134], stickR: [206, 134], dpad: [92, 108], face: [248, 108], bumpers: [42, 252] }
    if (isSwitch) return { stickL: [104, 100], stickR: [246, 100], dpad: [98, 138], face: [218, 138], bumpers: [42, 252] }
    return { stickL: [132, 136], stickR: [208, 136], dpad: [100, 108], face: [240, 108], bumpers: [42, 252] }
  }

  // ------------------------------------------------------------------ mini
  Loader {
    active: root.mini
    anchors.centerIn: parent
    sourceComponent: Rectangle {
      width: 30; height: 13; radius: 6
      color: "transparent"
      border.color: root.playerColor
      border.width: 2
      Rectangle { x: -3; y: 5; width: 10; height: 12; radius: 5; color: "transparent"; border.color: root.playerColor; border.width: 2; rotation: -18 }
      Rectangle { x: 23; y: 5; width: 10; height: 12; radius: 5; color: "transparent"; border.color: root.playerColor; border.width: 2; rotation: 18 }
      Rectangle { x: 3; y: 3.5; width: 5; height: 5; radius: 2.5; color: root.playerColor }
      Rectangle { x: 21; y: 3.5; width: 5; height: 5; radius: 2.5; color: root.playerColor }
    }
  }

  // ------------------------------------------------------------- full view
  Item {
    id: art
    visible: !root.mini
    width: 340
    height: 208
    scale: root.scale
    transformOrigin: Item.TopLeft

    // Grips (behind body)
    Rectangle { x: 18; y: 92; width: 74; height: 104; radius: 34; rotation: -14; color: root.bodyColor; border.color: root.bodyBorder; border.width: 1 }
    Rectangle { x: 248; y: 92; width: 74; height: 104; radius: 34; rotation: 14; color: root.bodyColor; border.color: root.bodyBorder; border.width: 1 }

    // Body
    Rectangle {
      id: body
      x: 16; y: 44; width: 308; height: 112; radius: 44
      color: root.bodyColor
      border.color: root.bodyBorder
      border.width: 1
    }

    // Player badge
    Rectangle {
      x: 8; y: 36; width: 12; height: 12; radius: 6
      color: root.playerColor
      border.color: root.bodyBorder
      border.width: 1
    }

    // ---------------- triggers (analog fill bars) + bumpers --------------
    TrigBar { x: root.geo.bumpers[0] + 6;  side: "l" }
    TrigBar { x: root.geo.bumpers[1] + 6; side: "r" }

    Bumper { x: root.geo.bumpers[0];  label: root.isPs ? "L1" : root.isSwitch ? "L" : "LB"; on: root.pressed(root.tables.bumperL) }
    Bumper { x: root.geo.bumpers[1]; label: root.isPs ? "R1" : root.isSwitch ? "R" : "RB"; on: root.pressed(root.tables.bumperR) }

    // ---------------- left stick ----------------------------------------
    Stick {
      cx: root.geo.stickL[0]
      cy: root.geo.stickL[1]
      rawX: root.stickX("l"); rawY: root.stickY("l")
      dz: root.dzFor("l")
      on: root.pressed(root.tables.stickL)
      accent: root.playerColor
    }

    // ---------------- right stick ---------------------------------------
    Stick {
      cx: root.geo.stickR[0]
      cy: root.geo.stickR[1]
      rawX: root.stickX("r"); rawY: root.stickY("r")
      dz: root.dzFor("r")
      on: root.pressed(root.tables.stickR)
      accent: root.playerColor
    }

    // ---------------- dpad ----------------------------------------------
    Dpad {
      cx: root.geo.dpad[0]
      cy: root.geo.dpad[1]
      up: root.pressed(root.tables.dpadUp)
      down: root.pressed(root.tables.dpadDown)
      left: root.pressed(root.tables.dpadLeft)
      right: root.pressed(root.tables.dpadRight)
      accent: root.playerColor
    }

    // ---------------- face buttons --------------------------------------
    FaceButton { cx: root.geo.face[0];      cy: root.geo.face[1] - 20; label: root.faceLabel("top");    on: root.pressed(root.tables.faceTop) }
    FaceButton { cx: root.geo.face[0];      cy: root.geo.face[1] + 20; label: root.faceLabel("bottom"); on: root.pressed(root.tables.faceBottom) }
    FaceButton { cx: root.geo.face[0] - 20; cy: root.geo.face[1];      label: root.faceLabel("left");   on: root.pressed(root.tables.faceLeft) }
    FaceButton { cx: root.geo.face[0] + 20; cy: root.geo.face[1];      label: root.faceLabel("right");  on: root.pressed(root.tables.faceRight) }

    // ---------------- center cluster ------------------------------------
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 62
      width: 120
      height: 74

      // Touchpad (PS)
      Rectangle {
        visible: root.isPs
        anchors.horizontalCenter: parent.horizontalCenter
        width: 74; height: 30; radius: 8; y: 0
        color: root.idleFill
        border.color: root.bodyBorder
        Rectangle {
          width: 10; height: 10; radius: 5
          anchors.centerIn: parent
          color: root.pressed(root.tables.centerExtra) ? root.playerColor : "transparent"
          border.color: root.dimGlyph
          border.width: 1
        }
      }

      CircleKey {
        cx: parent.width * 0.5
        cy: root.isPs ? 48 : 34
        r: root.isPs ? 13 : 11
        label: root.isPs ? "PS" : root.isSwitch ? "HOME" : "XBOX"
        labelSize: 6
        on: root.pressed(root.tables.centerTop)
        accent: root.playerColor
        showLabel: root.showLabels
      }
      CircleKey {
        cx: parent.width * 0.5 - (root.isSwitch ? 34 : 26)
        cy: root.isPs ? 52 : 40
        r: 7
        label: root.isSwitch ? "–" : "⧉"
        on: root.pressed(root.tables.centerLeft)
        accent: root.playerColor
        showLabel: root.showLabels
      }
      CircleKey {
        cx: parent.width * 0.5 + (root.isSwitch ? 34 : 26)
        cy: root.isPs ? 52 : 40
        r: 7
        label: root.isSwitch ? "+" : "☰"
        on: root.pressed(root.tables.centerRight)
        accent: root.playerColor
        showLabel: root.showLabels
      }
      CircleKey {
        visible: root.isSwitch
        cx: parent.width * 0.5 + 34
        cy: 56
        r: 6
        label: "▣"
        on: root.pressed(root.tables.centerExtra)
        accent: root.playerColor
        showLabel: root.showLabels
      }
    }

    // ---------------- captions ------------------------------------------
    Text {
      visible: root.showLabels && !root.isPs
      text: root.isSwitch ? "ZL / ZR analog" : "LT / RT analog"
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 2
      anchors.horizontalCenter: parent.horizontalCenter
      color: root.dimGlyph
      font.pixelSize: 8
      font.family: Style.font.family
    }
  }

  function faceLabel(pos) {
    if (root.isPs) return { top: "△", bottom: "×", left: "□", right: "○" }[pos]
    if (root.isSwitch) return { top: "X", bottom: "A", left: "Y", right: "B" }[pos]
    if (root.isXbox) return { top: "Y", bottom: "A", left: "X", right: "B" }[pos]
    return { top: "4", bottom: "1", left: "3", right: "2" }[pos]
  }

  // ============================================================ components
  component TrigBar : Item {
    id: trig
    property string side: "l"
    readonly property real h: 34
    width: 18
    height: h + 16
    y: 4

    readonly property real fillH: Math.max(0, Math.min(1, root.triggerNorm(side))) * h

    Rectangle {
      x: 2; y: 16; width: 14; height: trig.h; radius: 7
      color: root.idleFill
      border.color: root.bodyBorder
      border.width: 1
    }
    Rectangle {
      x: 2
      y: 16 + (trig.h - trig.fillH)
      width: 14
      height: trig.fillH
      radius: 7
      color: root.playerColor
      opacity: trig.fillH > 0 ? 0.9 : 0
      Behavior on y { NumberAnimation { duration: 40 } }
      Behavior on height { NumberAnimation { duration: 40 } }
    }
    Text {
      visible: root.showLabels
      anchors.horizontalCenter: parent.horizontalCenter
      y: 0
      text: root.isPs ? (trig.side === "l" ? "L2" : "R2") : root.isSwitch ? (trig.side === "l" ? "ZL" : "ZR") : (trig.side === "l" ? "LT" : "RT")
      color: root.dimGlyph
      font.pixelSize: 8
      font.family: Style.font.family
    }
  }

  component Bumper : Rectangle {
    id: bump
    property bool on: false
    property string label: ""
    y: 30
    width: 66
    height: 18
    radius: 9
    color: on ? root.playerColor : root.idleFill
    border.color: on ? root.playerColor : root.bodyBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: 60 } }
    Text {
      visible: root.showLabels
      anchors.centerIn: parent
      text: bump.label
      color: bump.on ? Color.popups.background : root.dimGlyph
      font.pixelSize: 8
      font.bold: true
      font.family: Style.font.family
    }
  }

  component Stick : Item {
    id: st
    property real cx: 0
    property real cy: 0
    property real rawX: 0
    property real rawY: 0
    property real dz: 0.1
    property bool on: false
    property color accent: root.playerColor

    x: cx - 25
    y: cy - 25
    width: 50
    height: 50

    readonly property var corrected: GamepadModel.applyStickDeadzone(rawX, rawY, dz)

    // base ring
    Rectangle {
      anchors.centerIn: parent
      width: 44; height: 44; radius: 22
      color: root.idleFill
      border.color: st.on ? st.accent : root.bodyBorder
      border.width: st.on ? 2 : 1
    }
    // deadzone ring (dashed look via alpha)
    Rectangle {
      anchors.centerIn: parent
      width: 44 * Math.max(0.05, st.dz) * 2 * 0.5 + 4
      height: width
      radius: width / 2
      color: "transparent"
      border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.5)
      border.width: 1
    }
    // raw dot
    Rectangle {
      width: 8; height: 8; radius: 4
      x: 22 - 4 + st.rawX * 18
      y: 22 - 4 + st.rawY * 18
      color: root.dimGlyph
      opacity: 0.5
    }
    // corrected dot
    Rectangle {
      width: 12; height: 12; radius: 6
      x: 22 - 6 + st.corrected.x * 18
      y: 22 - 6 + st.corrected.y * 18
      color: st.accent
      Behavior on x { NumberAnimation { duration: 30 } }
      Behavior on y { NumberAnimation { duration: 30 } }
    }
  }

  component Dpad : Item {
    id: dp
    property real cx: 0
    property real cy: 0
    property bool up: false
    property bool down: false
    property bool left: false
    property bool right: false
    property color accent: root.playerColor

    x: cx - 36
    y: cy - 36
    width: 72
    height: 72

    DpadArm { arm: "up";    on: dp.up }
    DpadArm { arm: "down";  on: dp.down }
    DpadArm { arm: "left";  on: dp.left }
    DpadArm { arm: "right"; on: dp.right }

    component DpadArm : Rectangle {
      id: arm
      property string arm: "up"
      property bool on: false
      width: 18
      height: 24
      radius: 4
      x: arm === "left" ? 0 : arm === "right" ? 54 : 27
      y: arm === "up" ? 0 : arm === "down" ? 48 : 24
      rotation: 0
      color: on ? dp.accent : root.idleFill
      border.color: on ? dp.accent : root.bodyBorder
      border.width: 1
      Behavior on color { ColorAnimation { duration: 60 } }
    }
  }

  component FaceButton : Rectangle {
    id: fb
    property real cx: 0
    property real cy: 0
    property string label: ""
    property bool on: false

    x: cx - 12
    y: cy - 12
    width: 24
    height: 24
    radius: 12
    color: on ? root.playerColor : root.idleFill
    border.color: on ? root.playerColor : root.bodyBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: 50 } }
    Text {
      visible: root.showLabels
      anchors.centerIn: parent
      text: fb.label
      color: fb.on ? Color.popups.background : root.dimGlyph
      font.pixelSize: 11
      font.bold: true
      font.family: Style.font.family
    }
  }

  component CircleKey : Rectangle {
    id: ck
    property real cx: 0
    property real cy: 0
    property real r: 8
    property string label: ""
    property bool on: false
    property color accent: root.playerColor
    property bool showLabel: true
    property int labelSize: 7

    x: cx - r
    y: cy - r
    width: r * 2
    height: r * 2
    radius: r
    color: on ? accent : root.idleFill
    border.color: on ? accent : root.bodyBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: 50 } }
    Text {
      visible: ck.showLabel
      anchors.centerIn: parent
      text: ck.label
      color: ck.on ? Color.popups.background : root.dimGlyph
      font.pixelSize: ck.labelSize
      font.bold: true
      font.family: Style.font.family
    }
  }
}
