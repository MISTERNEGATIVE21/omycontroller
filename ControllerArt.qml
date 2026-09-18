import QtQuick
import qs.Commons
import "GamepadModel.js" as GamepadModel

// Quatro — ControllerArt.qml
//
// Theme-aware, model-accurate controller rendering built from QML
// primitives (no SVG plugin, no external assets — hot-reloads cleanly and
// repaints instantly at input rate). Five layouts:
//
//   xbox     A/B/X/Y, asymmetric sticks, view/menu/guide/share
//   ps       DualSense ×/○/□/△, symmetric sticks, touchpad + glowing lightbar,
//            create/options, PS logo
//   switch   Nintendo glyph order (A right, B bottom, X top, Y left), +/-, home, capture
//   joystick single stick + hat + throttle (flight/arcade sticks, yokes)
//   generic  neutral 1..4 diamond
//
// Live behavior:
//   - face buttons / bumpers / dpad / center keys illuminate with glowing
//     drop-shadow / border highlights in playerColor
//   - PlayStation DualSense lightbar LED glows continuously in playerColor,
//     with active touchpad click halo and player indicator dot
//   - sticks render vector displacement stems and glowing thumbstick caps
//   - triggers are analog fill bars with active glow aura
//   - joystick view: hat lights from ABS_HAT0X/Y, throttle bar from extra axis,
//     trigger pill with glowing drop-shadow
//   - dashed inner ring on each stick shows the stored deadzone
//   - crisp responsive rendering in both mini mode (slot selector) and full mode (Overview)

Item {
  id: root

  property string layout: "generic"      // xbox | ps | switch | generic | joystick
  property color playerColor: Color.accent
  property var buttons: ({})             // js button index -> bool
  property var axes: []                  // normalized -1..1
  property var axisNames: []             // jstest header names ("X","Throttle"…)
  property var profile: ({})             // deadzone profile (stickL/stickR/...)
  property bool mini: false              // tiny silhouette for menu rows / slot selector
  property bool showLabels: true

  implicitWidth: mini ? 34 : 340 * scale
  implicitHeight: mini ? 20 : 208 * scale

  property real scale: 1.0
  readonly property bool isPs: layout === "ps"
  readonly property bool isSwitch: layout === "switch"
  readonly property bool isXbox: layout === "xbox"
  readonly property bool isJoystick: layout === "joystick"

  // Hat switch + throttle lever, only meaningful for the joystick layout.
  readonly property var extras: isJoystick ? GamepadModel.joystickExtras(axes, axisNames) : null

  // ---------------------------------------------------------------- tables
  readonly property var tables: GamepadModel.buttonTables(layout)
  readonly property var axisMap: GamepadModel.axesMap(layout, axes ? axes.length : 0, axisNames)

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

  // Any button actively pressed
  readonly property bool anyPress: {
    if (!buttons) return false
    for (var k in buttons) {
      if (buttons[k]) return true
    }
    return false
  }

  // -------------------------------------------------------------- palette
  readonly property color bodyColor: Color.popups.background
  readonly property color bodyBorder: (unknownPress || anyPress)
    ? root.playerColor
    : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.35)
  readonly property color glyphColor: Color.popups.text
  readonly property color dimGlyph: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.55)
  readonly property color idleFill: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.10)

  // ------------------------------------------------------------- geometry
  // Per-layout element centers inside the 340x208 canvas.
  readonly property var geo: {
    if (isXbox) return { stickL: [100, 112], stickR: [212, 140], dpad: [138, 128], face: [240, 108], bumpers: [42, 252] }
    if (isPs) return { stickL: [134, 134], stickR: [206, 134], dpad: [92, 108], face: [248, 108], bumpers: [42, 252] }
    if (isSwitch) return { stickL: [100, 112], stickR: [212, 140], dpad: [138, 128], face: [240, 108], bumpers: [42, 252] }
    return { stickL: [132, 136], stickR: [208, 136], dpad: [100, 108], face: [240, 108], bumpers: [42, 252] }
  }

  // ------------------------------------------------------------------ mini
  // Silhouette mode for slot selector and bar widget rows. Layout-aware,
  // vector-crisp, and reacts dynamically to live controller input.
  Loader {
    active: root.mini
    anchors.centerIn: parent
    sourceComponent: Item {
      width: 32
      height: 18

      // Main controller body silhouette
      Rectangle {
        anchors.centerIn: parent
        width: 28
        height: 14
        radius: 6
        color: root.anyPress ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22) : "transparent"
        border.color: root.playerColor
        border.width: 1.5

        Behavior on color { ColorAnimation { duration: 60 } }

        // Left grip
        Rectangle {
          x: -3; y: 4; width: 8; height: 11; radius: 4
          color: root.anyPress ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22) : "transparent"
          border.color: root.playerColor; border.width: 1.5; rotation: -18
        }

        // Right grip
        Rectangle {
          x: 23; y: 4; width: 8; height: 11; radius: 4
          color: root.anyPress ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.22) : "transparent"
          border.color: root.playerColor; border.width: 1.5; rotation: 18
        }

        // PS DualSense mini lightbar accent
        Rectangle {
          visible: root.isPs
          anchors.horizontalCenter: parent.horizontalCenter
          y: 1
          width: 10
          height: 1.5
          radius: 0.75
          color: root.playerColor
        }

        // Left stick dot (symmetric for PS, asymmetric high for Xbox/Switch)
        Rectangle {
          x: root.isPs ? 8 : 4
          y: (root.isXbox || root.isSwitch) ? 3 : 5
          width: 4; height: 4; radius: 2
          color: root.playerColor
        }

        // Right stick dot (symmetric for PS, asymmetric low for Xbox/Switch)
        Rectangle {
          x: root.isPs ? 16 : 18
          y: (root.isXbox || root.isSwitch) ? 6 : 5
          width: 4; height: 4; radius: 2
          color: root.playerColor
        }
      }
    }
  }

  // ------------------------------------------------------------- full view
  Item {
    id: art
    visible: !root.mini && !root.isJoystick
    width: 340
    height: 208
    scale: root.scale
    transformOrigin: Item.TopLeft

    // Grips (behind body)
    Rectangle {
      x: 18; y: 92; width: 74; height: 104; radius: 34; rotation: -14
      color: root.bodyColor
      border.color: root.bodyBorder
      border.width: root.anyPress ? 1.5 : 1
      Behavior on border.color { ColorAnimation { duration: 60 } }
    }
    Rectangle {
      x: 248; y: 92; width: 74; height: 104; radius: 34; rotation: 14
      color: root.bodyColor
      border.color: root.bodyBorder
      border.width: root.anyPress ? 1.5 : 1
      Behavior on border.color { ColorAnimation { duration: 60 } }
    }

    // Body
    Rectangle {
      id: body
      x: 16; y: 44; width: 308; height: 112; radius: 44
      color: root.bodyColor
      border.color: root.bodyBorder
      border.width: root.anyPress ? 1.5 : 1
      Behavior on border.color { ColorAnimation { duration: 60 } }
    }

    // Player badge
    Rectangle {
      x: 8; y: 36; width: 12; height: 12; radius: 6
      color: root.playerColor
      border.color: root.bodyBorder
      border.width: 1

      // Glowing aura around player badge
      Rectangle {
        anchors.centerIn: parent
        width: 18; height: 18; radius: 9
        color: "transparent"
        border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.4)
        border.width: 1.5
      }
    }

    // ---------------- triggers (analog fill bars) + bumpers --------------
    TrigBar { x: root.geo.bumpers[0] + 6; side: "l" }
    TrigBar { x: root.geo.bumpers[1] + 6; side: "r" }

    Bumper { x: root.geo.bumpers[0]; label: root.isPs ? "L1" : root.isSwitch ? "L" : "LB"; on: root.pressed(root.tables.bumperL) }
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
      y: 60
      width: 124
      height: 76

      // PlayStation DualSense Touchpad & Lightbar
      Item {
        visible: root.isPs
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: 82
        height: 38

        // DualSense Lightbar halo glow
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 4
          height: parent.height + 4
          radius: 10
          color: "transparent"
          border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.45)
          border.width: 3
          opacity: 0.85
        }

        // DualSense Lightbar crisp core
        Rectangle {
          anchors.centerIn: parent
          width: parent.width
          height: parent.height
          radius: 9
          color: "transparent"
          border.color: root.playerColor
          border.width: 1.5
        }

        // DualSense Touchpad surface
        Rectangle {
          id: psTouchpad
          anchors.centerIn: parent
          width: 76
          height: 32
          radius: 7
          color: root.pressed(root.tables.centerExtra)
            ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.3)
            : root.idleFill
          border.color: root.pressed(root.tables.centerExtra) ? root.playerColor : root.bodyBorder
          border.width: root.pressed(root.tables.centerExtra) ? 2 : 1
          Behavior on color { ColorAnimation { duration: 50 } }

          // Touchpad click indicator / glowing center dot
          Rectangle {
            width: 10; height: 10; radius: 5
            anchors.centerIn: parent
            color: root.pressed(root.tables.centerExtra) ? root.playerColor : "transparent"
            border.color: root.pressed(root.tables.centerExtra) ? root.playerColor : root.dimGlyph
            border.width: 1
          }
        }

        // DualSense player indicator dot below touchpad
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: psTouchpad.bottom
          anchors.topMargin: 3
          width: 5
          height: 3
          radius: 1.5
          color: root.playerColor
        }
      }

      // Center Guide / Home / PS Key
      CircleKey {
        cx: parent.width * 0.5
        cy: root.isPs ? 54 : 34
        r: root.isPs ? 12 : 11
        label: root.isPs ? "PS" : root.isSwitch ? "HOME" : "XBOX"
        labelSize: 6
        on: root.pressed(root.tables.centerTop)
        accent: root.playerColor
        showLabel: root.showLabels
      }

      // Left Center Key (View / Minus / Create)
      CircleKey {
        cx: parent.width * 0.5 - (root.isSwitch ? 34 : root.isPs ? 38 : 26)
        cy: root.isPs ? 36 : 40
        r: 7
        label: root.isSwitch ? "–" : root.isPs ? "⧉" : "⧉"
        on: root.pressed(root.tables.centerLeft)
        accent: root.playerColor
        showLabel: root.showLabels
      }

      // Right Center Key (Menu / Plus / Options)
      CircleKey {
        cx: parent.width * 0.5 + (root.isSwitch ? 34 : root.isPs ? 38 : 26)
        cy: root.isPs ? 36 : 40
        r: 7
        label: root.isSwitch ? "+" : root.isPs ? "☰" : "☰"
        on: root.pressed(root.tables.centerRight)
        accent: root.playerColor
        showLabel: root.showLabels
      }

      // Extra Center Key (Switch Capture / Xbox Share)
      CircleKey {
        visible: root.isSwitch || root.isXbox
        cx: parent.width * 0.5
        cy: root.isXbox ? 54 : 56
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

  // ------------------------------------------------- joystick full view
  // Single-stick flight/arcade layout: base plate, trigger pill with glow,
  // big stick with vector displacement stem, hat switch (ABS_HAT0X/Y),
  // base button cluster and throttle lever bar.
  Item {
    id: jart
    visible: !root.mini && root.isJoystick
    width: 340
    height: 208
    scale: root.scale
    transformOrigin: Item.TopLeft

    readonly property var ex: {
      if (root.extras) return root.extras
      return { hatX: 0, hatY: 0, hasHat: false, throttle: -1, hasThrottle: false }
    }

    // Base plate
    Rectangle {
      x: 14; y: 40; width: 312; height: 140; radius: 34
      color: root.bodyColor
      border.color: root.bodyBorder
      border.width: root.anyPress ? 1.5 : 1
      Behavior on border.color { ColorAnimation { duration: 60 } }
    }

    // Stick well
    Rectangle {
      x: 78; y: 72; width: 80; height: 80; radius: 40
      color: root.idleFill
      border.color: root.bodyBorder
      border.width: 1
    }

    // Trigger (button 0) pill with glowing highlight
    Rectangle {
      x: 36; y: 52; width: 84; height: 22; radius: 11
      color: root.pressed(root.tables.triggerL) ? root.playerColor : root.idleFill
      border.color: root.pressed(root.tables.triggerL) ? root.playerColor : root.bodyBorder
      border.width: root.pressed(root.tables.triggerL) ? 2 : 1
      scale: root.pressed(root.tables.triggerL) ? 1.04 : 1.0
      Behavior on color { ColorAnimation { duration: 50 } }
      Behavior on scale { NumberAnimation { duration: 50 } }

      // Trigger glow halo
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 8
        height: parent.height + 8
        radius: 13
        color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, root.pressed(root.tables.triggerL) ? 0.25 : 0)
        border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, root.pressed(root.tables.triggerL) ? 0.6 : 0)
        border.width: 2
        opacity: root.pressed(root.tables.triggerL) ? 1.0 : 0.0
        z: -1
        Behavior on opacity { NumberAnimation { duration: 60 } }
      }

      Text {
        visible: root.showLabels
        anchors.centerIn: parent
        text: "TRIGGER"
        color: root.pressed(root.tables.triggerL) ? Color.popups.background : root.dimGlyph
        font.pixelSize: 8
        font.bold: true
        font.family: Style.font.family
      }
    }

    // Main flight stick + deadzone preview ring
    Stick {
      cx: 118; cy: 112
      rawX: root.stickX("l"); rawY: root.stickY("l")
      dz: root.dzFor("l")
      on: root.pressed(root.tables.stickL)
      accent: root.playerColor
    }

    // Hat switch — driven by the HAT0 axis pair
    Dpad {
      cx: 216; cy: 74
      up: jart.ex.hatY < 0
      down: jart.ex.hatY > 0
      left: jart.ex.hatX < 0
      right: jart.ex.hatX > 0
      accent: root.playerColor
    }

    // Base button cluster 1..4
    FaceButton { cx: 198; cy: 128; label: "1"; on: root.pressed(root.tables.faceBottom) }
    FaceButton { cx: 224; cy: 128; label: "2"; on: root.pressed(root.tables.faceTop) }
    FaceButton { cx: 198; cy: 154; label: "3"; on: root.pressed(root.tables.faceLeft) }
    FaceButton { cx: 224; cy: 154; label: "4"; on: root.pressed(root.tables.faceRight) }

    // Extra base buttons 5/6
    CircleKey { cx: 258; cy: 128; r: 9; label: "5"; on: root.pressed(root.tables.bumperL); accent: root.playerColor; showLabel: root.showLabels }
    CircleKey { cx: 258; cy: 154; r: 9; label: "6"; on: root.pressed(root.tables.bumperR); accent: root.playerColor; showLabel: root.showLabels }

    // Spare keys 7/8
    CircleKey { cx: 146; cy: 62; r: 8; label: "7"; on: root.pressed(root.tables.centerTop); accent: root.playerColor; showLabel: root.showLabels }
    CircleKey { cx: 146; cy: 90; r: 8; label: "8"; on: root.pressed(root.tables.centerExtra); accent: root.playerColor; showLabel: root.showLabels }

    // Throttle lever bar
    TrigBar { x: 292; y: 76; side: "l"; labelOverride: "THR" }

    Text {
      visible: root.showLabels
      text: jart.ex.hasHat ? "hat + throttle live" : "stick + buttons live"
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
    if (root.isSwitch) return { top: "X", bottom: "B", left: "Y", right: "A" }[pos]
    if (root.isXbox) return { top: "Y", bottom: "A", left: "X", right: "B" }[pos]
    return { top: "4", bottom: "1", left: "3", right: "2" }[pos]
  }

  // ============================================================ components

  // ------------------------------------------------------------- TrigBar
  component TrigBar : Item {
    id: trig
    property string side: "l"
    property string labelOverride: ""
    readonly property real h: 34
    width: 18
    height: h + 16
    y: 4

    readonly property real fillH: Math.max(0, Math.min(1, root.triggerNorm(side))) * h

    Rectangle {
      x: 2; y: 16; width: 14; height: trig.h; radius: 7
      color: root.idleFill
      border.color: trig.fillH > 0 ? root.playerColor : root.bodyBorder
      border.width: 1
    }

    // Glow halo aura around active trigger fill
    Rectangle {
      x: 0; y: 14; width: 18; height: trig.h + 4; radius: 9
      color: "transparent"
      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, trig.fillH > 0 ? 0.45 * (trig.fillH / trig.h) : 0)
      border.width: 2
      opacity: trig.fillH > 0 ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 40 } }
    }

    // Trigger fill bar
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
      text: trig.labelOverride !== "" ? trig.labelOverride
           : root.isPs ? (trig.side === "l" ? "L2" : "R2")
           : root.isSwitch ? (trig.side === "l" ? "ZL" : "ZR")
           : (trig.side === "l" ? "LT" : "RT")
      color: trig.fillH > 0 ? root.playerColor : root.dimGlyph
      font.pixelSize: 8
      font.family: Style.font.family
    }
  }

  // -------------------------------------------------------------- Bumper
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
    border.width: on ? 2 : 1
    scale: on ? 1.04 : 1.0
    Behavior on color { ColorAnimation { duration: 60 } }
    Behavior on scale { NumberAnimation { duration: 60 } }

    // Glow halo drop-shadow
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 8
      height: parent.height + 8
      radius: 12
      color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, bump.on ? 0.22 : 0)
      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, bump.on ? 0.6 : 0)
      border.width: 2
      opacity: bump.on ? 1.0 : 0.0
      z: -1
      Behavior on opacity { NumberAnimation { duration: 60 } }
    }

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

  // --------------------------------------------------------------- Stick
  // Stick component with deadzone preview, vector displacement stem line,
  // and glowing thumbstick cap.
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
    readonly property real dispDist: Math.sqrt(corrected.x * corrected.x + corrected.y * corrected.y) * 18
    readonly property real dispAngle: Math.atan2(corrected.y, corrected.x) * 180 / Math.PI

    // Base ring
    Rectangle {
      anchors.centerIn: parent
      width: 44; height: 44; radius: 22
      color: root.idleFill
      border.color: st.on ? st.accent : (st.dispDist > 1 ? Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.4) : root.bodyBorder)
      border.width: st.on ? 2 : 1

      // Glow halo when L3/R3 clicked
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 10
        height: parent.height + 10
        radius: width / 2
        color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.25 : 0)
        border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.6 : 0)
        border.width: 2
        opacity: st.on ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 50 } }
      }
    }

    // Deadzone guide ring
    Rectangle {
      anchors.centerIn: parent
      width: 44 * Math.max(0.05, st.dz) * 2 * 0.5 + 4
      height: width
      radius: width / 2
      color: "transparent"
      border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.5)
      border.width: 1
    }

    // Vector displacement stem line
    Rectangle {
      x: 25
      y: 24
      width: st.dispDist
      height: 2
      radius: 1
      color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.5)
      transformOrigin: Item.Left
      rotation: st.dispAngle
      visible: st.dispDist > 1.5
      antialiasing: true
    }

    // Raw input ghost dot
    Rectangle {
      width: 6; height: 6; radius: 3
      x: 25 - 3 + st.rawX * 18
      y: 25 - 3 + st.rawY * 18
      color: root.dimGlyph
      opacity: 0.4
    }

    // Corrected vector stick cap with glowing aura
    Item {
      id: stickCap
      x: 25 - 8 + st.corrected.x * 18
      y: 25 - 8 + st.corrected.y * 18
      width: 16
      height: 16

      Behavior on x { NumberAnimation { duration: 25 } }
      Behavior on y { NumberAnimation { duration: 25 } }

      // Outer glow aura when deflected or clicked
      Rectangle {
        anchors.centerIn: parent
        width: 24
        height: 24
        radius: 12
        color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.35 : (st.dispDist > 2 ? 0.20 : 0))
        border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.7 : (st.dispDist > 2 ? 0.45 : 0))
        border.width: 1.5
        opacity: (st.on || st.dispDist > 2) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 50 } }
      }

      // Stick cap outer ring
      Rectangle {
        anchors.centerIn: parent
        width: st.on ? 14 : 16
        height: width
        radius: width / 2
        color: st.accent
        border.color: Color.popups.background
        border.width: 1.5
        Behavior on width { NumberAnimation { duration: 40 } }

        // Inner concave dot
        Rectangle {
          anchors.centerIn: parent
          width: 6; height: 6; radius: 3
          color: Color.popups.background
          opacity: 0.7
        }
      }
    }
  }

  // ---------------------------------------------------------------- Dpad
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
      border.width: on ? 2 : 1
      scale: on ? 1.05 : 1.0
      Behavior on color { ColorAnimation { duration: 60 } }
      Behavior on scale { NumberAnimation { duration: 60 } }

      // Glow halo
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 8
        height: parent.height + 8
        radius: 6
        color: Qt.rgba(dp.accent.r, dp.accent.g, dp.accent.b, arm.on ? 0.25 : 0)
        border.color: Qt.rgba(dp.accent.r, dp.accent.g, dp.accent.b, arm.on ? 0.6 : 0)
        border.width: 2
        opacity: arm.on ? 1.0 : 0.0
        z: -1
        Behavior on opacity { NumberAnimation { duration: 60 } }
      }
    }
  }

  // ---------------------------------------------------------- FaceButton
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
    border.width: on ? 2 : 1
    scale: on ? 1.06 : 1.0
    Behavior on color { ColorAnimation { duration: 50 } }
    Behavior on scale { NumberAnimation { duration: 50 } }

    // Glow halo drop-shadow aura
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 10
      height: parent.height + 10
      radius: width / 2
      color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, fb.on ? 0.25 : 0)
      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, fb.on ? 0.6 : 0)
      border.width: 2
      opacity: fb.on ? 1.0 : 0.0
      z: -1
      Behavior on opacity { NumberAnimation { duration: 60 } }
    }

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

  // ----------------------------------------------------------- CircleKey
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
    border.width: on ? 2 : 1
    scale: on ? 1.08 : 1.0
    Behavior on color { ColorAnimation { duration: 50 } }
    Behavior on scale { NumberAnimation { duration: 50 } }

    // Glow halo
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 8
      height: parent.height + 8
      radius: width / 2
      color: Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, ck.on ? 0.25 : 0)
      border.color: Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, ck.on ? 0.6 : 0)
      border.width: 2
      opacity: ck.on ? 1.0 : 0.0
      z: -1
      Behavior on opacity { NumberAnimation { duration: 50 } }
    }

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
