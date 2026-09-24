import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "GamepadModel.js" as GamepadModel

// Quatro — ControllerArt.qml
//
// Theme-aware, model-accurate controller rendering built from QML
// primitives (no SVG plugin — hot-reloads cleanly and repaints instantly at
// input rate) layered with ControllerImage button-cap art (assets/input) and,
// when a gamepadla catalog entry matches the pad, the controller's photo as
// the deck surface. Five layouts:
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
  property var gyro: null                // live 6-DOF gyro telemetry { ax, ay, az, gx, gy, gz, pitch, roll, yaw }
  property bool mini: false              // tiny silhouette for menu rows / slot selector
  property bool showLabels: true
  property bool interactive: !mini       // enables mouse/touch clicking and dragging
  property bool remapMode: false         // when true, clicks open button remapping dialog

  // Virtual interactive state (allows direct mouse/touch interaction)
  property var virtualButtons: ({})
  property var virtualSticks: ({
    "l": { x: 0.0, y: 0.0, active: false },
    "r": { x: 0.0, y: 0.0, active: false }
  })
  property var virtualTriggers: ({
    "l": 0.0,
    "r": 0.0
  })

  // Interactive pad signals
  signal buttonClicked(int index, bool pressed)
  signal dpadClicked(string dir, bool pressed)
  signal stickMoved(string side, real x, real y)
  signal stickReleased(string side)
  signal triggerMoved(string side, real value)
  signal requestRemap(string role, int buttonIndex, string currentLabel)

  // Live motion telemetry derivations with automatic fallbacks
  readonly property real rawPitch: {
    if (!gyro) return 0
    if (isFinite(Number(gyro.pitch))) return Number(gyro.pitch)
    var ax = Number(gyro.ax) || 0
    var ay = Number(gyro.ay) || 0
    var az = Number(gyro.az) || 9.81
    return Math.max(-85, Math.min(85, -Math.atan2(ay, Math.sqrt(ax * ax + az * az)) * 180 / Math.PI))
  }

  readonly property real rawRoll: {
    if (!gyro) return 0
    if (isFinite(Number(gyro.roll))) return Number(gyro.roll)
    var ax = Number(gyro.ax) || 0
    var az = Number(gyro.az) || 9.81
    return Math.max(-180, Math.min(180, Math.atan2(ax, az) * 180 / Math.PI))
  }

  readonly property real rawYaw: {
    if (!gyro) return 0
    if (isFinite(Number(gyro.yaw))) return Number(gyro.yaw)
    var gz = Number(gyro.gz) || 0
    return Math.max(-45, Math.min(45, gz * 25.0))
  }

  property real scale: 1.0
  readonly property real effScale: mini ? 1.0 : (width > 0 ? width / 340 : scale)

  implicitWidth: mini ? 34 : 340 * scale
  implicitHeight: mini ? 20 : 208 * scale

  property string modelLabel: ""
  property string maker: ""

  readonly property string effectiveLayout: {
    var l = String(layout || "").toLowerCase()
    var m = String(modelLabel || "").toLowerCase()
    var mk = String(maker || "").toLowerCase()

    if (l === "ps" || l === "playstation" || m.indexOf("dualsense") !== -1 || m.indexOf("dualshock") !== -1 || m.indexOf("playstation") !== -1 || mk.indexOf("sony") !== -1) {
      return "ps"
    }
    if (l === "switch" || l === "nintendo" || m.indexOf("switch") !== -1 || m.indexOf("joy-con") !== -1 || mk.indexOf("nintendo") !== -1) {
      return "switch"
    }
    if (l === "joystick" || m.indexOf("flight") !== -1 || m.indexOf("hotas") !== -1 || m.indexOf("yoke") !== -1 || m.indexOf("arcade") !== -1) {
      return "joystick"
    }
    if (l === "xbox" || m.indexOf("xbox") !== -1 || mk.indexOf("microsoft") !== -1 || m.indexOf("zhixu") !== -1) {
      return "xbox"
    }
    return l || "generic"
  }

  readonly property bool isPs: effectiveLayout === "ps"
  readonly property bool isSwitch: effectiveLayout === "switch"
  readonly property bool isXbox: effectiveLayout === "xbox"
  readonly property bool isJoystick: effectiveLayout === "joystick"

  // Hat switch + throttle lever, only meaningful for the joystick layout.
  readonly property var extras: isJoystick ? GamepadModel.joystickExtras(axes, axisNames) : null

  // ---------------------------------------------------------------- tables
  property string buttonPreset: ""
  readonly property var tables: GamepadModel.buttonTables(buttonPreset || (profile && profile.buttonPreset) || effectiveLayout, profile || buttonPreset)
  readonly property var axisMap: GamepadModel.axesMap(effectiveLayout, axes ? axes.length : 0, axisNames)
  property var virtualDpad: ({ up: false, down: false, left: false, right: false })
  function setVirtualDpad(dir, isDown) {
    var copy = Object.assign({}, virtualDpad)
    copy[dir] = !!isDown
    virtualDpad = copy
    dpadClicked(dir, isDown)
    buttonClicked(-1, isDown)
  }

  // Live rumble visual haptic parameters
  property bool rumbleActive: false
  property real rumbleWeak: 0.0
  property real rumbleStrong: 0.0

  function pressed(idx) {
    if (idx < 0) return false
    if (virtualButtons && virtualButtons[idx]) return true
    return !!(buttons && buttons[idx])
  }

  function setVirtualButton(idx, isDown) {
    if (idx < 0) return
    var copy = Object.assign({}, virtualButtons)
    if (isDown) {
      copy[idx] = true
    } else {
      delete copy[idx]
    }
    virtualButtons = copy
    buttonClicked(idx, isDown)
  }

  function setVirtualStick(side, sx, sy, isActive) {
    var copy = Object.assign({}, virtualSticks)
    copy[side] = { x: sx, y: sy, active: isActive }
    virtualSticks = copy
    if (isActive) {
      stickMoved(side, sx, sy)
    } else {
      stickReleased(side)
    }
  }

  function setVirtualTrigger(side, val) {
    var copy = Object.assign({}, virtualTriggers)
    copy[side] = val
    virtualTriggers = copy
    triggerMoved(side, val)
  }

  function axisValue(idx, fallback) {
    if (idx === -1) return fallback
    if (!axes || idx >= axes.length) return fallback
    var v = Number(axes[idx])
    return isFinite(v) ? v : fallback
  }

  function triggerNorm(side) {
    if (virtualTriggers && isFinite(Number(virtualTriggers[side])) && Number(virtualTriggers[side]) > 0) {
      return Number(virtualTriggers[side])
    }
    // Check digital trigger button first for discrete button-based triggers
    if (pressed(side === "l" ? tables.triggerL : tables.triggerR)) {
      return 1.0
    }
    if (!axes || axes.length === 0) {
      return 0.0
    }
    var fallback = (isXbox || layout === "generic") ? -1 : 0
    var raw = axisValue(side === "l" ? axisMap.lt : axisMap.rt, fallback)
    return GamepadModel.triggerNorm(layout, raw)
  }

  function stickX(side) {
    if (virtualSticks && virtualSticks[side] && virtualSticks[side].active) {
      return virtualSticks[side].x
    }
    return axisValue(side === "l" ? axisMap.lx : axisMap.rx, 0)
  }

  function stickY(side) {
    if (virtualSticks && virtualSticks[side] && virtualSticks[side].active) {
      return virtualSticks[side].y
    }
    return axisValue(side === "l" ? axisMap.ly : axisMap.ry, 0)
  }

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
    if (virtualButtons) {
      for (var vk in virtualButtons) {
        if (virtualButtons[vk]) return true
      }
    }
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
    if (isXbox || isSwitch) return { stickL: [92, 102], stickR: [212, 140], dpad: [128, 140], face: [248, 102], bumpers: [64, 214] }
    if (isPs) return { stickL: [126, 140], stickR: [214, 140], dpad: [92, 102], face: [248, 102], bumpers: [64, 214] }
    return { stickL: [92, 102], stickR: [212, 140], dpad: [128, 140], face: [248, 102], bumpers: [64, 214] }
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
      rotation: Math.max(-45, Math.min(45, root.rawRoll * 0.75))
      Behavior on rotation {
        SpringAnimation { spring: 3.5; damping: 0.35; epsilon: 0.1 }
      }

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
    scale: root.effScale
    transformOrigin: Item.TopLeft
    x: (root.width - 340 * root.effScale) / 2
    y: (root.height - 208 * root.effScale) / 2

    // 3D Gyro Motion Transform: tilts, rolls and yaws dynamically with physical controller motion
    property real rumblePhase: 0
    NumberAnimation on rumblePhase {
      running: root.rumbleActive
      from: 0; to: Math.PI * 20
      duration: 800
      loops: Animation.Infinite
    }

    transform: [
      Translate {
        id: rumbleTranslate
        x: root.rumbleActive ? (Math.sin(root.rumblePhase * 3.7) * (1.8 * Math.max(0.2, (root.rumbleWeak + root.rumbleStrong)))) : 0
        y: root.rumbleActive ? (Math.cos(root.rumblePhase * 4.3) * (1.2 * Math.max(0.2, (root.rumbleWeak + root.rumbleStrong)))) : 0
      },
      Rotation {
        id: pitchRot
        origin.x: 170
        origin.y: 104
        axis { x: 1; y: 0; z: 0 }
        angle: Math.max(-45, Math.min(45, root.rawPitch * 0.75))
        Behavior on angle {
          SpringAnimation { spring: 3.5; damping: 0.35; epsilon: 0.05 }
        }
      },
      Rotation {
        id: yawRot
        origin.x: 170
        origin.y: 104
        axis { x: 0; y: 1; z: 0 }
        angle: Math.max(-35, Math.min(35, root.rawYaw * 0.65))
        Behavior on angle {
          SpringAnimation { spring: 3.5; damping: 0.35; epsilon: 0.05 }
        }
      },
      Rotation {
        id: rollRot
        origin.x: 170
        origin.y: 104
        axis { x: 0; y: 0; z: 1 }
        angle: Math.max(-60, Math.min(60, root.rawRoll * 0.85))
        Behavior on angle {
          SpringAnimation { spring: 3.8; damping: 0.32; epsilon: 0.05 }
        }
      }
    ]

    // 1. Layer 0: Deep Ambient Drop Shadow (Soft depth cast onto deck card)
    Shape {
      anchors.fill: parent
      anchors.topMargin: 8
      layer.enabled: true
      layer.smooth: true
      opacity: 0.36

      ShapePath {
        strokeWidth: 0
        fillColor: "#000000"
        startX: 170; startY: 24
        PathCubic { control1X: 192; control1Y: 24; control2X: 202; control2Y: 22; x: 214; y: 18 }
        PathCubic { control1X: 226; control1Y: 14; control2X: 254; control2Y: 14; x: 268; y: 18 }
        PathCubic { control1X: 280; control1Y: 24; control2X: 292; control2Y: 42; x: 298; y: 64 }
        PathCubic { control1X: 306; control1Y: 88; control2X: 308; control2Y: 106; x: 308; y: 124 }
        PathCubic { control1X: 308; control1Y: 152; control2X: 298; control2Y: 178; x: 280; y: 196 }
        PathCubic { control1X: 270; control1Y: 204; control2X: 254; control2Y: 202; x: 242; y: 194 }
        PathCubic { control1X: 226; control1Y: 184; control2X: 214; control2Y: 176; x: 204; y: 168 }
        PathCubic { control1X: 194; control1Y: 160; control2X: 182; control2Y: 158; x: 170; y: 158 }
        PathCubic { control1X: 158; control1Y: 158; control2X: 146; control2Y: 160; x: 136; y: 168 }
        PathCubic { control1X: 126; control1Y: 176; control2X: 114; control2Y: 184; x: 98; y: 194 }
        PathCubic { control1X: 86; control1Y: 202; control2X: 70; control2Y: 204; x: 60; y: 196 }
        PathCubic { control1X: 42; control1Y: 178; control2X: 32; control2Y: 152; x: 32; y: 124 }
        PathCubic { control1X: 32; control1Y: 106; control2X: 34; control2Y: 88; x: 42; y: 64 }
        PathCubic { control1X: 48; control1Y: 42; control2X: 60; control2Y: 24; x: 72; y: 18 }
        PathCubic { control1X: 86; control1Y: 14; control2X: 114; control2Y: 14; x: 126; y: 18 }
        PathCubic { control1X: 138; control1Y: 22; control2X: 148; control2Y: 24; x: 170; y: 24 }
      }
    }

    // 2. Layer 1: Contact Drop Shadow (Soft proximity ground occlusion)
    Shape {
      anchors.fill: parent
      anchors.topMargin: 4
      layer.enabled: true
      layer.smooth: true
      opacity: 0.18

      ShapePath {
        strokeWidth: 0
        fillColor: "#000000"
        startX: 170; startY: 24
        PathCubic { control1X: 192; control1Y: 24; control2X: 202; control2Y: 22; x: 214; y: 18 }
        PathCubic { control1X: 226; control1Y: 14; control2X: 254; control2Y: 14; x: 268; y: 18 }
        PathCubic { control1X: 280; control1Y: 24; control2X: 292; control2Y: 42; x: 298; y: 64 }
        PathCubic { control1X: 306; control1Y: 88; control2X: 308; control2Y: 106; x: 308; y: 124 }
        PathCubic { control1X: 308; control1Y: 152; control2X: 298; control2Y: 178; x: 280; y: 196 }
        PathCubic { control1X: 270; control1Y: 204; control2X: 254; control2Y: 202; x: 242; y: 194 }
        PathCubic { control1X: 226; control1Y: 184; control2X: 214; control2Y: 176; x: 204; y: 168 }
        PathCubic { control1X: 194; control1Y: 160; control2X: 182; control2Y: 158; x: 170; y: 158 }
        PathCubic { control1X: 158; control1Y: 158; control2X: 146; control2Y: 160; x: 136; y: 168 }
        PathCubic { control1X: 126; control1Y: 176; control2X: 114; control2Y: 184; x: 98; y: 194 }
        PathCubic { control1X: 86; control1Y: 202; control2X: 70; control2Y: 204; x: 60; y: 196 }
        PathCubic { control1X: 42; control1Y: 178; control2X: 32; control2Y: 152; x: 32; y: 124 }
        PathCubic { control1X: 32; control1Y: 106; control2X: 34; control2Y: 88; x: 42; y: 64 }
        PathCubic { control1X: 48; control1Y: 42; control2X: 60; control2Y: 24; x: 72; y: 18 }
        PathCubic { control1X: 86; control1Y: 14; control2X: 114; control2Y: 14; x: 126; y: 18 }
        PathCubic { control1X: 138; control1Y: 22; control2X: 148; control2Y: 24; x: 170; y: 24 }
      }
    }

    // 3. Top Deck Plate (Solid sculpted Xbox Series controller body)
    Shape {
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true

      ShapePath {
        strokeWidth: root.anyPress ? 2 : 1.2
        strokeColor: root.bodyBorder
        fillGradient: LinearGradient {
          x1: 170; y1: 18; x2: 170; y2: 200
          GradientStop { position: 0.0; color: Qt.lighter(root.bodyColor, 1.15) }
          GradientStop { position: 0.35; color: root.bodyColor }
          GradientStop { position: 0.85; color: Qt.darker(root.bodyColor, 1.14) }
          GradientStop { position: 1.0; color: Qt.darker(root.bodyColor, 1.26) }
        }
        startX: 170; startY: 24
        PathCubic { control1X: 192; control1Y: 24; control2X: 202; control2Y: 22; x: 214; y: 18 }
        PathCubic { control1X: 226; control1Y: 14; control2X: 254; control2Y: 14; x: 268; y: 18 }
        PathCubic { control1X: 280; control1Y: 24; control2X: 292; control2Y: 42; x: 298; y: 64 }
        PathCubic { control1X: 306; control1Y: 88; control2X: 308; control2Y: 106; x: 308; y: 124 }
        PathCubic { control1X: 308; control1Y: 152; control2X: 298; control2Y: 178; x: 280; y: 196 }
        PathCubic { control1X: 270; control1Y: 204; control2X: 254; control2Y: 202; x: 242; y: 194 }
        PathCubic { control1X: 226; control1Y: 184; control2X: 214; control2Y: 176; x: 204; y: 168 }
        PathCubic { control1X: 194; control1Y: 160; control2X: 182; control2Y: 158; x: 170; y: 158 }
        PathCubic { control1X: 158; control1Y: 158; control2X: 146; control2Y: 160; x: 136; y: 168 }
        PathCubic { control1X: 126; control1Y: 176; control2X: 114; control2Y: 184; x: 98; y: 194 }
        PathCubic { control1X: 86; control1Y: 202; control2X: 70; control2Y: 204; x: 60; y: 196 }
        PathCubic { control1X: 42; control1Y: 178; control2X: 32; control2Y: 152; x: 32; y: 124 }
        PathCubic { control1X: 32; control1Y: 106; control2X: 34; control2Y: 88; x: 42; y: 64 }
        PathCubic { control1X: 48; control1Y: 42; control2X: 60; control2Y: 24; x: 72; y: 18 }
        PathCubic { control1X: 86; control1Y: 14; control2X: 114; control2Y: 14; x: 126; y: 18 }
        PathCubic { control1X: 138; control1Y: 22; control2X: 148; control2Y: 24; x: 170; y: 24 }
      }

      // Subtle top crown specular ridge catching ambient light on left shoulder
      ShapePath {
        strokeWidth: 1.2
        strokeColor: Qt.rgba(1, 1, 1, 0.16)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: 72; startY: 19
        PathCubic { control1X: 86; control1Y: 15; control2X: 114; control2Y: 15; x: 126; y: 19 }
      }

      // Subtle top crown specular ridge catching ambient light on right shoulder
      ShapePath {
        strokeWidth: 1.2
        strokeColor: Qt.rgba(1, 1, 1, 0.16)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: 214; startY: 19
        PathCubic { control1X: 226; control1Y: 15; control2X: 254; control2Y: 15; x: 268; y: 19 }
      }
    }

    // DualSense Two-Tone Faceplate Collar & Wings (Signature PS5 Styling)
    Shape {
      visible: root.isPs
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true
      opacity: 0.90

      // Left Outer Wing
      ShapePath {
        strokeWidth: 1.2
        strokeColor: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.40)
        fillColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.10)
        startX: 126; startY: 18
        PathCubic { control1X: 114; control1Y: 14; control2X: 86; control2Y: 14; x: 72; y: 18 }
        PathCubic { control1X: 60; control1Y: 24; control2X: 48; control2Y: 42; x: 42; y: 64 }
        PathCubic { control1X: 34; control1Y: 88; control2X: 32; control2Y: 106; x: 32; y: 124 }
        PathCubic { control1X: 32; control1Y: 152; control2X: 42; control2Y: 178; x: 60; y: 196 }
        PathCubic { control1X: 70; control1Y: 204; control2X: 86; control2Y: 202; x: 98; y: 194 }
        PathCubic { control1X: 82; control1Y: 170; control2X: 74; control2Y: 130; x: 78; y: 92 }
        PathCubic { control1X: 82; control1Y: 58; control2X: 98; control2Y: 34; x: 126; y: 18 }
      }

      // Right Outer Wing
      ShapePath {
        strokeWidth: 1.2
        strokeColor: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.40)
        fillColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.10)
        startX: 214; startY: 18
        PathCubic { control1X: 226; control1Y: 14; control2X: 254; control2Y: 14; x: 268; y: 18 }
        PathCubic { control1X: 280; control1Y: 24; control2X: 292; control2Y: 42; x: 298; y: 64 }
        PathCubic { control1X: 306; control1Y: 88; control2X: 308; control2Y: 106; x: 308; y: 124 }
        PathCubic { control1X: 308; control1Y: 152; control2X: 298; control2Y: 178; x: 280; y: 196 }
        PathCubic { control1X: 270; control1Y: 204; control2X: 254; control2Y: 202; x: 242; y: 194 }
        PathCubic { control1X: 258; control1Y: 170; control2X: 266; control2Y: 130; x: 262; y: 92 }
        PathCubic { control1X: 258; control1Y: 58; control2X: 242; control2Y: 34; x: 214; y: 18 }
      }
    }

    // Switch Pro Subtle Inner Circuit Accent
    Rectangle {
      visible: root.isSwitch
      anchors.centerIn: parent
      width: 140; height: 90
      radius: 45
      color: "transparent"
      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.20)
      border.width: 1
    }

    // USB-C Top Connector Port (Precision Hardware Detail)
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 20
      width: 22; height: 6; radius: 3
      color: Qt.rgba(0, 0, 0, 0.70)
      border.color: Qt.rgba(root.bodyBorder.r, root.bodyBorder.g, root.bodyBorder.b, 0.35)
      border.width: 1

      // Gold contact pins
      Rectangle {
        anchors.centerIn: parent
        width: 14; height: 1.5; radius: 0.75
        color: Qt.rgba(1, 0.84, 0, 0.35)
      }
    }

    // Wireless Sync / Pairing Button
    Rectangle {
      x: 198; y: 21
      width: 6; height: 4; radius: 2
      color: Qt.rgba(0, 0, 0, 0.50)
      border.color: Qt.rgba(root.bodyBorder.r, root.bodyBorder.g, root.bodyBorder.b, 0.30)
      border.width: 1
    }

    // 6. Sculpted Ergonomic Outer Palm Grip Flanks (Standard Xbox Series Contour)
    // Refined vulcanized rubber flank zones hugging the outer horn curvature without
    // cluttering face buttons or thumbsticks, finished with laser-etched micro-dot stippling.
    Shape {
      anchors.fill: parent
      layer.enabled: true
      layer.smooth: true

      // --- Left Grip Flank Base ---
      ShapePath {
        strokeWidth: 1.0
        strokeColor: Qt.rgba(0, 0, 0, 0.40)
        fillGradient: LinearGradient {
          x1: 30; y1: 120; x2: 56; y2: 135
          GradientStop { position: 0.0; color: "#1e222b" }
          GradientStop { position: 0.45; color: "#13161c" }
          GradientStop { position: 1.0; color: "#0a0c10" }
        }
        startX: 40; startY: 74
        PathCubic { control1X: 33; control1Y: 96; control2X: 31; control2Y: 122; x: 32; y: 140 }
        PathCubic { control1X: 33; control1Y: 158; control2X: 42; control2Y: 178; x: 58; y: 194 }
        PathCubic { control1X: 64; control1Y: 196; control2X: 72; control2Y: 194; x: 78; y: 188 }
        PathCubic { control1X: 72; control1Y: 176; control2X: 58; control2Y: 156; x: 52; y: 136 }
        PathCubic { control1X: 48; control1Y: 116; control2X: 48; control2Y: 94; x: 50; y: 76 }
        PathCubic { control1X: 47; control1Y: 74; control2X: 43; control2Y: 74; x: 40; y: 74 }
      }

      // --- Right Grip Flank Base ---
      ShapePath {
        strokeWidth: 1.0
        strokeColor: Qt.rgba(0, 0, 0, 0.40)
        fillGradient: LinearGradient {
          x1: 310; y1: 120; x2: 284; y2: 135
          GradientStop { position: 0.0; color: "#1e222b" }
          GradientStop { position: 0.45; color: "#13161c" }
          GradientStop { position: 1.0; color: "#0a0c10" }
        }
        startX: 300; startY: 74
        PathCubic { control1X: 307; control1Y: 96; control2X: 309; control2Y: 122; x: 308; y: 140 }
        PathCubic { control1X: 307; control1Y: 158; control2X: 298; control2Y: 178; x: 282; y: 194 }
        PathCubic { control1X: 276; control1Y: 196; control2X: 268; control2Y: 194; x: 262; y: 188 }
        PathCubic { control1X: 268; control1Y: 176; control2X: 282; control2Y: 156; x: 288; y: 136 }
        PathCubic { control1X: 292; control1Y: 116; control2X: 292; control2Y: 94; x: 290; y: 76 }
        PathCubic { control1X: 293; control1Y: 74; control2X: 297; control2Y: 74; x: 300; y: 74 }
      }

      // --- Left Flank Specular Ridge Catch ---
      ShapePath {
        strokeWidth: 1.2
        strokeColor: Qt.rgba(1, 1, 1, 0.12)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: 39; startY: 82
        PathCubic { control1X: 33; control1Y: 104; control2X: 33; control2Y: 126; x: 38; y: 150 }
      }

      // --- Right Flank Specular Ridge Catch ---
      ShapePath {
        strokeWidth: 1.2
        strokeColor: Qt.rgba(1, 1, 1, 0.12)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: 301; startY: 82
        PathCubic { control1X: 307; control1Y: 104; control2X: 307; control2Y: 126; x: 302; y: 150 }
      }
    }

    // --- Visual Dual-Motor Rumble Haptics (Left Heavy LF / Right Fast HF) ---
    Item {
      anchors.fill: parent
      visible: root.rumbleActive
      opacity: root.rumbleActive ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      // Left Grip: Heavy Low-Frequency Shaker (Coil + Eccentric Counterweight)
      Item {
        x: 42; y: 126
        width: 34; height: 34

        // Radiating Haptic Resonance Ripple Wave
        Rectangle {
          anchors.centerIn: parent
          width: 26 + Math.sin(art.rumblePhase * 2.5) * 14
          height: width
          radius: width / 2
          color: "transparent"
          border.color: Qt.rgba(1.0, 0.45, 0.15, 0.65 * Math.max(0.3, root.rumbleStrong))
          border.width: 1.5
        }

        // Motor Casing
        Rectangle {
          anchors.centerIn: parent
          width: 22; height: 26; radius: 4
          color: Qt.rgba(0.08, 0.09, 0.12, 0.85)
          border.color: Qt.rgba(1.0, 0.50, 0.20, 0.75 * Math.max(0.3, root.rumbleStrong))
          border.width: 1.2
        }

        // Copper Coil Core
        Rectangle {
          anchors.centerIn: parent
          width: 14; height: 16; radius: 2
          color: Qt.rgba(0.85, 0.40, 0.15, 0.75)
        }

        // Rotating Heavy Eccentric Rotor Mass
        Rectangle {
          anchors.centerIn: parent
          width: 18; height: 6; radius: 3
          color: Qt.rgba(1.0, 0.65, 0.25, 0.95)
          rotation: (art.rumblePhase * 180 / Math.PI) * 1.5
        }
      }

      // Right Grip: High-Frequency Precision Spinner (Coil + Lightweight Flyweight)
      Item {
        x: 290; y: 126
        width: 34; height: 34

        // Radiating Haptic Resonance Ripple Wave
        Rectangle {
          anchors.centerIn: parent
          width: 24 + Math.cos(art.rumblePhase * 3.2) * 12
          height: width
          radius: width / 2
          color: "transparent"
          border.color: Qt.rgba(0.35, 0.75, 1.0, 0.65 * Math.max(0.3, root.rumbleWeak))
          border.width: 1.5
        }

        // Motor Casing
        Rectangle {
          anchors.centerIn: parent
          width: 20; height: 24; radius: 4
          color: Qt.rgba(0.08, 0.09, 0.12, 0.85)
          border.color: Qt.rgba(0.35, 0.75, 1.0, 0.75 * Math.max(0.3, root.rumbleWeak))
          border.width: 1.2
        }

        // High-Speed Blue/Cyan Armature Core
        Rectangle {
          anchors.centerIn: parent
          width: 12; height: 14; radius: 2
          color: Qt.rgba(0.20, 0.60, 0.95, 0.75)
        }

        // Rapid Spinning Counterweight
        Rectangle {
          anchors.centerIn: parent
          width: 16; height: 5; radius: 2.5
          color: Qt.rgba(0.50, 0.85, 1.0, 0.95)
          rotation: (art.rumblePhase * 180 / Math.PI) * 2.8
        }
      }
    }

    // Micro-Stippled Tactile Texture Overlay on Palm Grips
    Item {
      anchors.fill: parent
      opacity: 0.32

      // Left Flank Stippling Dots
      Column {
        x: 41; y: 104
        spacing: 5
        Repeater {
          model: 8
          delegate: Row {
            id: leftDotRow
            property int rowIdx: index
            spacing: 4
            x: rowIdx > 4 ? (rowIdx - 4) * 2 : 0
            Repeater {
              model: (leftDotRow.rowIdx >= 2 && leftDotRow.rowIdx <= 6) ? 3 : 2
              delegate: Rectangle { width: 1.5; height: 1.5; radius: 0.75; color: "#FFFFFF" }
            }
          }
        }
      }

      // Right Flank Stippling Dots
      Column {
        x: 291; y: 104
        spacing: 5
        Repeater {
          model: 8
          delegate: Row {
            id: rightDotRow
            property int rowIdx: index
            spacing: 4
            x: rowIdx > 4 ? -(rowIdx - 4) * 2 : 0
            Repeater {
              model: (rightDotRow.rowIdx >= 2 && rightDotRow.rowIdx <= 6) ? 3 : 2
              delegate: Rectangle { width: 1.5; height: 1.5; radius: 0.75; color: "#FFFFFF" }
            }
          }
        }
      }
    }

    // Integrated Player Slot LEDs on lower center bridge
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 126
      spacing: 4
      visible: !root.isPs

      Repeater {
        model: 4
        Rectangle {
          required property int index
          width: 4; height: 4; radius: 2
          color: index === 0 ? root.playerColor : Qt.rgba(root.dimGlyph.r, root.dimGlyph.g, root.dimGlyph.b, 0.22)
          border.color: index === 0 ? root.playerColor : "transparent"
          border.width: 1
        }
      }
    }

    // ---------------- 2.5D Integrated Shoulder & Trigger Units ----------
    ShoulderUnit {
      side: "l"
      xPos: root.geo.bumpers[0]
      trigRole: "triggerL"
      bumpRole: "bumperL"
      trigLabel: GamepadModel.buttonLabel(root.effectiveLayout, "triggerL", root.profile)
      bumpLabel: GamepadModel.buttonLabel(root.effectiveLayout, "bumperL", root.profile)
      bumpIndex: root.tables.bumperL
      trigIndex: root.tables.triggerL
      bumpOn: root.pressed(root.tables.bumperL)
      bumpArtSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.effectiveLayout, "bumperL", root.profile))
      trigArtSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.effectiveLayout, "triggerL", root.profile))
    }

    ShoulderUnit {
      side: "r"
      xPos: root.geo.bumpers[1]
      trigRole: "triggerR"
      bumpRole: "bumperR"
      trigLabel: GamepadModel.buttonLabel(root.effectiveLayout, "triggerR", root.profile)
      bumpLabel: GamepadModel.buttonLabel(root.effectiveLayout, "bumperR", root.profile)
      bumpIndex: root.tables.bumperR
      trigIndex: root.tables.triggerR
      bumpOn: root.pressed(root.tables.bumperR)
      bumpArtSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.effectiveLayout, "bumperR", root.profile))
      trigArtSource: Qt.resolvedUrl(GamepadModel.buttonArt(root.effectiveLayout, "triggerR", root.profile))
    }

    // ---------------- left stick ----------------------------------------
    Stick {
      side: "l"
      cx: root.geo.stickL[0]
      cy: root.geo.stickL[1]
      rawX: root.stickX("l"); rawY: root.stickY("l")
      dz: root.dzFor("l")
      on: root.pressed(root.tables.stickL)
      stickIndex: root.tables.stickL
      accent: "#C084FC" // Figma pastel lavender
    }

    // ---------------- right stick ---------------------------------------
    Stick {
      side: "r"
      cx: root.geo.stickR[0]
      cy: root.geo.stickR[1]
      rawX: root.stickX("r"); rawY: root.stickY("r")
      dz: root.dzFor("r")
      on: root.pressed(root.tables.stickR)
      stickIndex: root.tables.stickR
      accent: "#34D399" // Figma pastel mint
    }

    // ---------------- dpad ----------------------------------------------
    Dpad {
      cx: root.geo.dpad[0]
      cy: root.geo.dpad[1]
      up: (root.virtualDpad && root.virtualDpad.up) || GamepadModel.isDpadActive("up", root.buttons, root.axes, root.tables, root.axisMap)
      down: (root.virtualDpad && root.virtualDpad.down) || GamepadModel.isDpadActive("down", root.buttons, root.axes, root.tables, root.axisMap)
      dpadLeft: (root.virtualDpad && root.virtualDpad.left) || GamepadModel.isDpadActive("left", root.buttons, root.axes, root.tables, root.axisMap)
      dpadRight: (root.virtualDpad && root.virtualDpad.right) || GamepadModel.isDpadActive("right", root.buttons, root.axes, root.tables, root.axisMap)
      idxUp: root.tables.dpadUp
      idxDown: root.tables.dpadDown
      idxLeft: root.tables.dpadLeft
      idxRight: root.tables.dpadRight
      accent: root.playerColor
    }

    // ---------------- face buttons --------------------------------------
    FaceButton { cx: root.geo.face[0];      cy: root.geo.face[1] - 18; label: root.faceLabel("top");    pos: "top";    role: "faceTop";    buttonIndex: root.tables.faceTop;    on: root.pressed(root.tables.faceTop);    artSource: Qt.resolvedUrl(GamepadModel.faceArt(root.effectiveLayout, "top", root.profile)) }
    FaceButton { cx: root.geo.face[0];      cy: root.geo.face[1] + 18; label: root.faceLabel("bottom"); pos: "bottom"; role: "faceBottom"; buttonIndex: root.tables.faceBottom; on: root.pressed(root.tables.faceBottom); artSource: Qt.resolvedUrl(GamepadModel.faceArt(root.effectiveLayout, "bottom", root.profile)) }
    FaceButton { cx: root.geo.face[0] - 18; cy: root.geo.face[1];      label: root.faceLabel("left");   pos: "left";   role: "faceLeft";   buttonIndex: root.tables.faceLeft;   on: root.pressed(root.tables.faceLeft);   artSource: Qt.resolvedUrl(GamepadModel.faceArt(root.effectiveLayout, "left", root.profile)) }
    FaceButton { cx: root.geo.face[0] + 18; cy: root.geo.face[1];      label: root.faceLabel("right");  pos: "right";  role: "faceRight";  buttonIndex: root.tables.faceRight;  on: root.pressed(root.tables.faceRight);  artSource: Qt.resolvedUrl(GamepadModel.faceArt(root.effectiveLayout, "right", root.profile)) }

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

        // Recessed chassis well socket
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 2
          height: parent.height + 2
          radius: 10
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: Qt.rgba(0, 0, 0, 0.65)
          border.width: 1
        }

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

        // 3D Touchpad surface
        Rectangle {
          id: psTouchpad
          anchors.centerIn: parent
          // Tactile click depression: sinks 1.5px into socket on click
          y: root.pressed(root.tables.centerExtra) ? 4.5 : 3
          width: 76
          height: 32
          radius: 7
          color: root.pressed(root.tables.centerExtra)
            ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.3)
            : Qt.rgba(root.bodyColor.r, root.bodyColor.g, root.bodyColor.b, 0.90)
          border.color: root.pressed(root.tables.centerExtra) ? root.playerColor : root.bodyBorder
          border.width: root.pressed(root.tables.centerExtra) ? 2 : 1
          scale: root.pressed(root.tables.centerExtra) ? 0.97 : (psTouchMouse.containsMouse ? 1.02 : 1.0)
          Behavior on color { ColorAnimation { duration: 25 } }
          Behavior on y { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
          Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

          MouseArea {
            id: psTouchMouse
            anchors.fill: parent
            enabled: root.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.setVirtualButton(root.tables.centerExtra, true)
            onReleased: root.setVirtualButton(root.tables.centerExtra, false)
            onCanceled: root.setVirtualButton(root.tables.centerExtra, false)
          }

          // Top chamfer specular highlight
          Rectangle {
            x: 4; y: 1
            width: parent.width - 8
            height: 2
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.20)
          }

          // Bottom shadow seam
          Rectangle {
            x: 4; y: parent.height - 2
            width: parent.width - 8
            height: 1
            color: Qt.rgba(0, 0, 0, 0.50)
          }

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
        cy: root.isPs ? 54 : (root.isXbox ? 28 : 34)
        r: root.isPs ? 12 : (root.isXbox ? 13 : 11)
        label: root.isPs ? "PS" : root.isSwitch ? "HOME" : "XBOX"
        labelSize: 6
        role: "centerTop"
        buttonIndex: root.tables.centerTop
        on: root.pressed(root.tables.centerTop)
        accent: root.playerColor
        showLabel: !root.isXbox && !root.isSwitch && root.showLabels
        artSource: Qt.resolvedUrl(GamepadModel.centerArt(root.effectiveLayout, "guide"))
      }

      // Left Center Key (View / Minus / Create)
      CircleKey {
        cx: parent.width * 0.5 - (root.isSwitch ? 34 : root.isPs ? 38 : 28)
        cy: root.isPs ? 36 : (root.isXbox ? 44 : 40)
        r: 7
        label: root.isSwitch ? "–" : "⧉"
        role: "centerLeft"
        buttonIndex: root.tables.centerLeft
        on: root.pressed(root.tables.centerLeft)
        accent: root.playerColor
        showLabel: root.showLabels
        artSource: Qt.resolvedUrl(GamepadModel.centerArt(root.effectiveLayout, "left"))
      }

      // Right Center Key (Menu / Plus / Options)
      CircleKey {
        cx: parent.width * 0.5 + (root.isSwitch ? 34 : root.isPs ? 38 : 28)
        cy: root.isPs ? 36 : (root.isXbox ? 44 : 40)
        r: 7
        label: root.isSwitch ? "+" : "☰"
        role: "centerRight"
        buttonIndex: root.tables.centerRight
        on: root.pressed(root.tables.centerRight)
        accent: root.playerColor
        showLabel: root.showLabels
        artSource: Qt.resolvedUrl(GamepadModel.centerArt(root.effectiveLayout, "right"))
      }

      // Extra Center Key (Switch Capture / Xbox Share)
      CircleKey {
        visible: root.isSwitch || root.isXbox
        cx: parent.width * 0.5
        cy: root.isXbox ? 50 : 56
        r: root.isXbox ? 6 : 5
        label: root.isXbox ? "⮝" : "▣"
        labelSize: 6
        role: "centerExtra"
        buttonIndex: root.tables.centerExtra
        on: root.pressed(root.tables.centerExtra)
        accent: root.playerColor
        showLabel: root.showLabels
        artSource: Qt.resolvedUrl(GamepadModel.centerArt(root.effectiveLayout, "extra"))
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
    scale: root.effScale
    transformOrigin: Item.TopLeft
    x: (root.width - 340 * root.effScale) / 2
    y: (root.height - 208 * root.effScale) / 2

    // 3D Gyro Motion Transform: tilts, rolls and yaws dynamically with physical flight stick motion
    transform: [
      Rotation {
        origin.x: 170
        origin.y: 104
        axis { x: 1; y: 0; z: 0 }
        angle: Math.max(-45, Math.min(45, root.rawPitch * 0.75))
        Behavior on angle {
          SpringAnimation { spring: 3.5; damping: 0.35; epsilon: 0.05 }
        }
      },
      Rotation {
        origin.x: 170
        origin.y: 104
        axis { x: 0; y: 1; z: 0 }
        angle: Math.max(-35, Math.min(35, root.rawYaw * 0.65))
        Behavior on angle {
          SpringAnimation { spring: 3.5; damping: 0.35; epsilon: 0.05 }
        }
      },
      Rotation {
        origin.x: 170
        origin.y: 104
        axis { x: 0; y: 0; z: 1 }
        angle: Math.max(-60, Math.min(60, root.rawRoll * 0.85))
        Behavior on angle {
          SpringAnimation { spring: 3.8; damping: 0.32; epsilon: 0.05 }
        }
      }
    ]

    readonly property var ex: {
      if (root.extras) return root.extras
      return { hatX: 0, hatY: 0, hasHat: false, throttle: -1, hasThrottle: false }
    }

    // Layer 0: Ambient drop shadow
    Rectangle {
      x: 14; y: 48; width: 312; height: 140; radius: 34
      color: "#000000"
      opacity: 0.36
    }

    // Layer 1: Contact drop shadow
    Rectangle {
      x: 14; y: 44; width: 312; height: 140; radius: 34
      color: "#000000"
      opacity: 0.28
    }

    // Layer 2: 3D Lower base extrusion
    Rectangle {
      x: 14; y: 44.5; width: 312; height: 140; radius: 34
      color: Qt.darker(root.bodyColor, 1.45)
      border.color: Qt.rgba(0, 0, 0, 0.75)
      border.width: 1.5
    }

    // Layer 3: Top Base Plate
    Rectangle {
      x: 14; y: 40; width: 312; height: 140; radius: 34
      color: root.bodyColor
      border.color: root.bodyBorder
      border.width: root.anyPress ? 1.5 : 1
      Behavior on border.color { ColorAnimation { duration: 60 } }

      // Layer 4: Upper perimeter specular highlight
      Rectangle {
        x: 6; y: 2; width: parent.width - 12; height: 3; radius: 1.5
        color: Qt.rgba(1, 1, 1, 0.16)
      }

      // 4 Non-slip rubber feet
      Rectangle { x: 18; y: 16; width: 14; height: 14; radius: 7; color: Qt.rgba(0, 0, 0, 0.45); border.color: Qt.rgba(0, 0, 0, 0.65); border.width: 1 }
      Rectangle { x: parent.width - 32; y: 16; width: 14; height: 14; radius: 7; color: Qt.rgba(0, 0, 0, 0.45); border.color: Qt.rgba(0, 0, 0, 0.65); border.width: 1 }
      Rectangle { x: 18; y: parent.height - 30; width: 14; height: 14; radius: 7; color: Qt.rgba(0, 0, 0, 0.45); border.color: Qt.rgba(0, 0, 0, 0.65); border.width: 1 }
      Rectangle { x: parent.width - 32; y: parent.height - 30; width: 14; height: 14; radius: 7; color: Qt.rgba(0, 0, 0, 0.45); border.color: Qt.rgba(0, 0, 0, 0.65); border.width: 1 }
    }

    // 3D Recessed Flight Stick Gimbal Bowl
    Rectangle {
      x: 74; y: 68; width: 88; height: 88; radius: 44
      color: Qt.rgba(0, 0, 0, 0.55)
      border.color: Qt.rgba(0, 0, 0, 0.75)
      border.width: 1

      // Gimbal inner chamfer
      Rectangle {
        anchors.centerIn: parent
        width: 78; height: 78; radius: 39
        color: Qt.rgba(0, 0, 0, 0.30)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
      }
    }

    // 3D Flight Trigger (Button 0)
    Item {
      x: 36; y: 52; width: 84; height: 22

      // Socket recess
      Rectangle {
        anchors.fill: parent
        radius: 11
        color: Qt.rgba(0, 0, 0, 0.45)
        border.color: Qt.rgba(0, 0, 0, 0.65)
        border.width: 1
      }

      // Trigger blade with click depression
      Rectangle {
        id: jtrigBlade
        anchors.centerIn: parent
        // Sinks 2px down when pressed
        anchors.verticalCenterOffset: root.pressed(root.tables.triggerL) ? 1.5 : 0
        width: parent.width - 2
        height: parent.height - 2
        radius: 10
        color: root.pressed(root.tables.triggerL) ? root.playerColor : Qt.darker(root.bodyColor, 1.15)
        border.color: root.pressed(root.tables.triggerL) ? root.playerColor : root.bodyBorder
        border.width: root.pressed(root.tables.triggerL) ? 1.5 : 1
        scale: root.pressed(root.tables.triggerL) ? 0.97 : (jtrigMouse.containsMouse ? 1.04 : 1.0)

        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 25 } }
        Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

        MouseArea {
          id: jtrigMouse
          anchors.fill: parent
          enabled: root.interactive
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPressed: root.setVirtualButton(root.tables.triggerL, true)
          onReleased: root.setVirtualButton(root.tables.triggerL, false)
          onCanceled: root.setVirtualButton(root.tables.triggerL, false)
        }

        // Glow halo
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 6
          height: parent.height + 6
          radius: 12
          color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, root.pressed(root.tables.triggerL) ? 0.30 : 0)
          border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, root.pressed(root.tables.triggerL) ? 0.70 : 0)
          border.width: 1.5
          opacity: root.pressed(root.tables.triggerL) ? 1.0 : 0.0
          z: -1
          Behavior on opacity { NumberAnimation { duration: 50 } }
        }

        // Top specular highlight
        Rectangle {
          x: 4; y: 1.5
          width: parent.width - 8
          height: 2
          radius: 1
          color: Qt.rgba(1, 1, 1, root.pressed(root.tables.triggerL) ? 0.40 : 0.15)
        }

        Text {
          visible: root.showLabels
          anchors.centerIn: parent
          text: "TRIGGER"
          color: root.pressed(root.tables.triggerL) ? Color.popups.background : root.glyphColor
          font.pixelSize: 8
          font.bold: true
          font.family: Style.font.family
        }
      }
    }

    // Main flight stick + deadzone preview ring
    Stick {
      side: "l"
      cx: 118; cy: 112
      rawX: root.stickX("l"); rawY: root.stickY("l")
      dz: root.dzFor("l")
      on: root.pressed(root.tables.stickL)
      stickIndex: root.tables.stickL
      accent: root.playerColor
    }

    // Hat switch — driven by the HAT0 axis pair
    Dpad {
      cx: 216; cy: 74
      up: jart.ex.hatY < 0
      down: jart.ex.hatY > 0
      dpadLeft: jart.ex.hatX < 0
      dpadRight: jart.ex.hatX > 0
      accent: root.playerColor
    }

    // Base button cluster 1..4
    FaceButton { cx: 198; cy: 128; label: "1"; buttonIndex: root.tables.faceBottom; on: root.pressed(root.tables.faceBottom) }
    FaceButton { cx: 224; cy: 128; label: "2"; buttonIndex: root.tables.faceTop; on: root.pressed(root.tables.faceTop) }
    FaceButton { cx: 198; cy: 154; label: "3"; buttonIndex: root.tables.faceLeft; on: root.pressed(root.tables.faceLeft) }
    FaceButton { cx: 224; cy: 154; label: "4"; buttonIndex: root.tables.faceRight; on: root.pressed(root.tables.faceRight) }

    // Extra base buttons 5/6
    CircleKey { cx: 258; cy: 128; r: 9; label: "5"; buttonIndex: root.tables.bumperL; on: root.pressed(root.tables.bumperL); accent: root.playerColor; showLabel: root.showLabels }
    CircleKey { cx: 258; cy: 154; r: 9; label: "6"; buttonIndex: root.tables.bumperR; on: root.pressed(root.tables.bumperR); accent: root.playerColor; showLabel: root.showLabels }

    // Spare keys 7/8
    CircleKey { cx: 146; cy: 62; r: 8; label: "7"; buttonIndex: root.tables.centerTop; on: root.pressed(root.tables.centerTop); accent: root.playerColor; showLabel: root.showLabels }
    CircleKey { cx: 146; cy: 90; r: 8; label: "8"; buttonIndex: root.tables.centerExtra; on: root.pressed(root.tables.centerExtra); accent: root.playerColor; showLabel: root.showLabels }

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
    var role = pos === "top" ? "faceTop" : pos === "bottom" ? "faceBottom" : pos === "left" ? "faceLeft" : "faceRight"
    return GamepadModel.buttonLabel(root.effectiveLayout, role, root.profile)
  }

  // ============================================================ components

  // -------------------------------------------------------- ShoulderUnit
  // Standard Xbox Series Sculpted Ergonomic Shoulder & Trigger Assembly
  // Aerodynamic contoured bumper wing and recessed analog trigger blade with
  // natural 3D depth, specular chamfers, and interactive analog travel.
  component ShoulderUnit : Item {
    id: su
    property string side: "l" // "l" or "r"
    property real xPos: 0
    property real yPos: 6
    property string trigLabel: ""
    property string bumpLabel: ""
    property string trigRole: isLeft ? "triggerL" : "triggerR"
    property string bumpRole: isLeft ? "bumperL" : "bumperR"
    property string bumpArtSource: ""
    property string trigArtSource: ""
    property bool bumpOn: false
    property int bumpIndex: -1
    property int trigIndex: -1
    property real dragPull: 0
    readonly property real fillAmount: Math.max(0, Math.min(1, root.triggerNorm(side)))
    readonly property bool isLeft: side === "l"

    NumberAnimation {
      id: trigReleaseAnim
      target: su
      property: "dragPull"
      to: 0
      duration: 180
      easing.type: Easing.OutQuad
      onFinished: {
        root.setVirtualTrigger(su.side, 0.0)
        root.setVirtualButton(su.trigIndex, false)
      }
    }
    onDragPullChanged: {
      if (trigReleaseAnim.running) {
        root.setVirtualTrigger(su.side, dragPull)
      }
    }

    x: xPos
    y: yPos
    width: 64
    height: 36

    // Subtle ergonomic shoulder angle matching the downward contour of the Xbox body
    rotation: isLeft ? -3.5 : 3.5
    transformOrigin: isLeft ? Item.BottomRight : Item.BottomLeft

    // 1. Recessed 3D Chassis Socket Well (Negative Z-depth in top cowl)
    Rectangle {
      x: 0; y: 4
      width: parent.width
      height: 30
      radius: 6
      color: Qt.darker(root.bodyColor, 1.60)
      border.color: Qt.rgba(0, 0, 0, 0.65)
      border.width: 1
      z: -1

      // Top socket chamfer edge
      Rectangle {
        x: 2; y: 1
        width: parent.width - 4
        height: 1
        color: Qt.rgba(root.bodyBorder.r, root.bodyBorder.g, root.bodyBorder.b, 0.35)
      }
    }

    // 2. Xbox Series Sculpted Analog Trigger Blade (LT / RT / L2 / R2 / ZL / ZR)
    // Sits in the upper chamber behind the bumper, smoothly depressing on analog pull
    Rectangle {
      id: trigBlade
      x: su.isLeft ? 6 : 4
      // Sinks downward as trigger is pulled
      y: 1 + su.fillAmount * 4.5
      width: parent.width - 10
      height: 20
      radius: 5
      z: 0

      color: su.fillAmount > 0.05
        ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.35)
        : (trigMouse.containsMouse ? Qt.lighter(Qt.darker(root.bodyColor, 1.25), 1.15) : Qt.darker(root.bodyColor, 1.25))
      border.color: su.fillAmount > 0.05
        ? root.playerColor
        : (trigMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.60) : Qt.rgba(0, 0, 0, 0.70))
      border.width: su.fillAmount > 0.05 ? 1.5 : 1

      Behavior on y { NumberAnimation { duration: 40 } }
      Behavior on color { ColorAnimation { duration: 50 } }

      MouseArea {
        id: trigMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap(su.trigRole, su.trigIndex, su.trigLabel)
            return
          }
          trigReleaseAnim.stop()
          var pull = Math.max(0.25, Math.min(1.0, (mouse.y + 4) / parent.height))
          su.dragPull = pull
          root.setVirtualTrigger(su.side, pull)
          root.setVirtualButton(su.trigIndex, true)
        }
        onPositionChanged: function(mouse) {
          if (pressed && !root.remapMode) {
            var pull = Math.max(0.0, Math.min(1.0, (mouse.y + 4) / parent.height))
            su.dragPull = pull
            root.setVirtualTrigger(su.side, pull)
            root.setVirtualButton(su.trigIndex, pull > 0.1)
          }
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            trigReleaseAnim.restart()
          }
        }
        onCanceled: trigReleaseAnim.restart()
      }

      // 3 Tactile Micro-Ridge Grip Lines (Xbox Series Trigger Grip Texture)
      Column {
        anchors.top: parent.top
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2
        opacity: su.fillAmount > 0.05 ? 0.40 : 0.65

        Repeater {
          model: 3
          Rectangle {
            width: 24; height: 1; radius: 0.5
            color: Qt.rgba(1, 1, 1, 0.18)
          }
        }
      }

      // Top Specular Crown Chamfer Highlight
      Rectangle {
        x: 3; y: 1
        width: parent.width - 6
        height: 1
        color: su.fillAmount > 0.05 ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(1, 1, 1, 0.20)
      }

      // Precision Glowing Travel Fill Line along top edge
      Rectangle {
        x: 2; y: 1
        width: Math.max(0, (parent.width - 4) * su.fillAmount)
        height: 1.5
        radius: 0.75
        color: root.playerColor
        visible: su.fillAmount > 0.02
        opacity: 0.95
      }

      Image {
        id: trigCapImg
        visible: su.trigArtSource !== "" && status === Image.Ready
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 1
        width: 20
        height: 14
        source: su.trigArtSource
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        layer.enabled: visible
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: su.fillAmount > 0.40 ? Color.popups.background : root.glyphColor
        }
      }

      // Trigger Label (Tucked cleanly at the top of the trigger blade)
      Text {
        visible: root.showLabels && (!trigCapImg.visible || trigCapImg.status !== Image.Ready)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 1
        text: su.trigLabel
        color: su.fillAmount > 0.40 ? Color.popups.background : root.glyphColor
        font.pixelSize: 8
        font.bold: true
        font.family: Style.font.family
      }
    }

    // 3. Xbox Series Sculpted Ergonomic Bumper Wing (LB / RB / L1 / R1 / L / R)
    // Seamlessly overlaps the trigger base and seats into the front top contour of the shell
    Rectangle {
      id: bumperPlate
      x: 0
      y: su.bumpOn ? 14 : 12
      width: parent.width
      height: 19
      radius: 6
      z: 1

      color: su.bumpOn
        ? root.playerColor
        : (bumpMouse.containsMouse ? Qt.lighter(Qt.darker(root.bodyColor, 1.12), 1.15) : Qt.darker(root.bodyColor, 1.12))
      border.color: su.bumpOn
        ? root.playerColor
        : (bumpMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.65) : Qt.rgba(root.bodyBorder.r, root.bodyBorder.g, root.bodyBorder.b, 0.40))
      border.width: su.bumpOn ? 1.5 : 1
      scale: su.bumpOn ? 0.97 : (bumpMouse.containsMouse ? 1.02 : 1.0)

      Behavior on y { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
      Behavior on color { ColorAnimation { duration: 25 } }
      Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

      MouseArea {
        id: bumpMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap(su.bumpRole, su.bumpIndex, su.bumpLabel)
          } else {
            root.setVirtualButton(su.bumpIndex, true)
          }
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            root.setVirtualButton(su.bumpIndex, false)
          }
        }
        onCanceled: root.setVirtualButton(su.bumpIndex, false)
      }

      // Reactive Glow Bloom Halo on Click or Hover
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 6
        height: parent.height + 6
        radius: 8
        color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, su.bumpOn ? 0.35 : 0)
        border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, su.bumpOn ? 0.75 : 0)
        border.width: 1.5
        opacity: (su.bumpOn || bumpMouse.containsMouse) ? 1.0 : 0.0
        z: -1
        Behavior on opacity { NumberAnimation { duration: 50 } }
      }

      // Top Specular Crown Bevel (Reflective Upper Chamfer)
      Rectangle {
        x: 3; y: 1
        width: parent.width - 6
        height: 1.2
        radius: 0.6
        color: su.bumpOn ? Qt.rgba(1, 1, 1, 0.65) : Qt.rgba(1, 1, 1, 0.25)
      }

      // Subtle Upper Surface Horizon Reflection
      Rectangle {
        x: 4; y: 2.5
        width: parent.width - 8
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.05)
        visible: !su.bumpOn
      }

      Image {
        id: bumpCapImg
        visible: su.bumpArtSource !== "" && status === Image.Ready
        anchors.centerIn: parent
        width: 24
        height: 14
        source: su.bumpArtSource
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        layer.enabled: visible
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: su.bumpOn ? Color.popups.background : root.glyphColor
        }
      }

      // Bumper Label
      Text {
        visible: !bumpCapImg.visible || bumpCapImg.status !== Image.Ready
        anchors.centerIn: parent
        text: su.bumpLabel
        color: su.bumpOn ? Color.popups.background : root.glyphColor
        font.pixelSize: 9
        font.bold: true
        font.family: Style.font.family
      }
    }
  }

  // ------------------------------------------------------------- TrigBar
  component TrigBar : Item {
    id: trig
    property real xPos: 0
    property real yPos: 16
    property string side: "l"
    property string labelOverride: ""

    x: xPos
    y: yPos
    width: 44
    height: 15

    readonly property real fillAmount: Math.max(0, Math.min(1, root.triggerNorm(side)))

    Rectangle {
      anchors.fill: parent
      radius: 4
      color: root.idleFill
      border.color: trig.fillAmount > 0.05 ? root.playerColor : root.bodyBorder
      border.width: trig.fillAmount > 0.05 ? 1.5 : 1

      // Analog Fill Level
      Rectangle {
        x: 2; y: 2
        width: Math.max(0, (parent.width - 4) * trig.fillAmount)
        height: parent.height - 4
        radius: 3
        color: root.playerColor
        opacity: trig.fillAmount > 0.05 ? 0.75 : 0.0
        Behavior on opacity { NumberAnimation { duration: 40 } }
      }

      Text {
        anchors.centerIn: parent
        text: trig.labelOverride !== "" ? trig.labelOverride
             : root.isPs ? (trig.side === "l" ? "L2" : "R2")
             : root.isSwitch ? (trig.side === "l" ? "ZL" : "ZR")
             : (trig.side === "l" ? "LT" : "RT")
        color: trig.fillAmount > 0.45 ? Color.popups.background : root.glyphColor
        font.pixelSize: 8
        font.bold: true
        font.family: Style.font.family
      }
    }
  }

  // -------------------------------------------------------------- Bumper
  component Bumper : Rectangle {
    id: bump
    property real xPos: 0
    property real yPos: 34
    property bool on: false
    property string label: ""
    property string artSource: ""

    x: xPos
    y: yPos
    width: 56
    height: 16
    radius: 6
    color: on ? root.playerColor : root.idleFill
    border.color: on ? root.playerColor : root.bodyBorder
    border.width: on ? 2 : 1
    scale: on ? 1.04 : 1.0
    Behavior on color { ColorAnimation { duration: 60 } }
    Behavior on scale { NumberAnimation { duration: 60 } }

    // Glow halo drop-shadow
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 6
      height: parent.height + 6
      radius: 8
      color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, bump.on ? 0.22 : 0)
      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, bump.on ? 0.6 : 0)
      border.width: 2
      opacity: bump.on ? 1.0 : 0.0
      z: -1
      Behavior on opacity { NumberAnimation { duration: 60 } }
    }

    Image {
      visible: bump.artSource !== ""
      anchors.fill: parent
      anchors.margins: 2
      source: bump.artSource
      fillMode: Image.PreserveAspectFit
      mipmap: true
      layer.enabled: visible
      layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: bump.on ? root.playerColor : root.glyphColor
      }
    }

    Text {
      visible: root.showLabels && bump.artSource === ""
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
    property string side: "l"
    property int stickIndex: -1
    property real dragX: 0
    property real dragY: 0
    property bool isDragging: false

    ParallelAnimation {
      id: springReturnAnim
      NumberAnimation { target: st; property: "dragX"; to: 0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
      NumberAnimation { target: st; property: "dragY"; to: 0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
      onFinished: {
        st.isDragging = false
        root.setVirtualStick(st.side, 0, 0, false)
      }
    }

    onDragXChanged: {
      if (isDragging) root.setVirtualStick(st.side, dragX, dragY, true)
    }
    onDragYChanged: {
      if (isDragging) root.setVirtualStick(st.side, dragX, dragY, true)
    }

    Timer {
      id: l3ReleaseTimer
      interval: 180
      repeat: false
      onTriggered: root.setVirtualButton(st.stickIndex, false)
    }

    x: cx - 26
    y: cy - 26
    width: 52
    height: 52

    readonly property var corrected: GamepadModel.applyStickDeadzone(rawX, rawY, dz)
    readonly property real dispDist: Math.sqrt(corrected.x * corrected.x + corrected.y * corrected.y) * 18
    readonly property real dispAngle: Math.atan2(corrected.y, corrected.x) * 180 / Math.PI

    // 1. Recessed Spherical Gimbal Well Socket
    // Outer chassis chamfer bezel ring
    Rectangle {
      anchors.centerIn: parent
      width: 50; height: 50; radius: 25
      color: "transparent"
      border.color: Qt.rgba(0, 0, 0, 0.65)
      border.width: 1

      // Top-left chamfer highlight
      Rectangle {
        x: 4; y: 2
        width: 22; height: 2; radius: 1
        color: Qt.rgba(1, 1, 1, 0.18)
      }
    }

    // Deep spherical cavity (concentric depth rings)
    Rectangle {
      anchors.centerIn: parent
      width: 46; height: 46; radius: 23
      color: Qt.rgba(0, 0, 0, 0.65)
      border.color: st.on ? st.accent : (st.dispDist > 1 ? Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.45) : Qt.rgba(root.bodyBorder.r, root.bodyBorder.g, root.bodyBorder.b, 0.50))
      border.width: st.on ? 2 : 1

      // Mid bowl depth ring
      Rectangle {
        anchors.centerIn: parent
        width: 36; height: 36; radius: 18
        color: Qt.rgba(0, 0, 0, 0.35)
        border.color: Qt.rgba(0, 0, 0, 0.55)
        border.width: 1
      }

      // Gimbal base socket floor
      Rectangle {
        anchors.centerIn: parent
        width: 24; height: 24; radius: 12
        color: Qt.rgba(0, 0, 0, 0.25)
      }

      // L3/R3 Click Glow Halo
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 6
        height: parent.height + 6
        radius: width / 2
        color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.30 : 0)
        border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.70 : 0)
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
      border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.45)
      border.width: 1
    }

    // 2. 3D Cylindrical Stem Linkage (Extrudes from socket center to deflected thumb cap)
    Item {
      x: 26; y: 26 - 3
      width: st.dispDist
      height: 6
      transformOrigin: Item.Left
      rotation: st.dispAngle
      visible: st.dispDist > 1.2

      // Stem upper light facet
      Rectangle {
        x: 0; y: 0; width: parent.width; height: 3; radius: 1.5
        color: Qt.rgba(1, 1, 1, 0.30)
      }
      // Stem core accent
      Rectangle {
        x: 0; y: 1.5; width: parent.width; height: 2
        color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.45)
      }
      // Stem underside shadow facet
      Rectangle {
        x: 0; y: 3; width: parent.width; height: 3; radius: 1.5
        color: Qt.rgba(0, 0, 0, 0.70)
      }
    }

    // Raw input ghost dot
    Rectangle {
      width: 5; height: 5; radius: 2.5
      x: 26 - 2.5 + st.rawX * 18
      y: 26 - 2.5 + st.rawY * 18
      color: root.dimGlyph
      opacity: 0.35
    }

    // 3. 3D Sculpted Thumbcap Assembly
    Item {
      id: stickCap
      x: 26 - 10 + st.corrected.x * 18
      // Physical microswitch click depression: sinks 1.5px into socket on click
      y: 26 - 10 + st.corrected.y * 18 + (st.on ? 1.5 : 0)
      width: 20
      height: 20
      scale: st.on ? 0.94 : (stickMouse.containsMouse && !st.isDragging ? 1.05 : 1.0)

      Behavior on x { NumberAnimation { duration: 25 } }
      Behavior on y { NumberAnimation { duration: 25 } }
      Behavior on scale { NumberAnimation { duration: 40 } }

      // Cap Ambient Drop Shadow (casts shadow into well)
      Rectangle {
        x: 1 + st.corrected.x * 2
        y: 2.5 + st.corrected.y * 2
        width: 20; height: 20; radius: 10
        color: Qt.rgba(0, 0, 0, 0.50)
        z: -1
      }

      // Outer glow aura when deflected, hovered, or clicked
      Rectangle {
        anchors.centerIn: parent
        width: 28; height: 28; radius: 14
        color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.40 : (st.dispDist > 2 ? 0.22 : 0))
        border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, st.on ? 0.80 : (st.dispDist > 2 ? 0.50 : 0))
        border.width: 1.5
        opacity: (st.on || st.dispDist > 2 || (stickMouse.containsMouse && !st.isDragging)) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 50 } }
      }

      // 3D Knurled Outer Grip Rim (Dark textured elastomer tire)
      Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.rgba(0.12, 0.13, 0.16, 1.0)
        border.color: Qt.rgba(0, 0, 0, 0.85)
        border.width: 1

        // Top-left specular rim highlight
        Rectangle {
          x: 2; y: 1.5
          width: 12; height: 2.5; radius: 1.25
          color: Qt.rgba(1, 1, 1, 0.38)
        }

        // Bottom-right shadow rim
        Rectangle {
          x: 6; y: parent.height - 3.5
          width: 12; height: 2; radius: 1
          color: Qt.rgba(0, 0, 0, 0.70)
        }

        // 4 Tactile Knurling Micro-Notches (0°, 90°, 180°, 270°)
        Rectangle { x: 9.25; y: 0.5; width: 1.5; height: 2; color: Qt.rgba(0, 0, 0, 0.6) }
        Rectangle { x: 9.25; y: 17.5; width: 1.5; height: 2; color: Qt.rgba(0, 0, 0, 0.6) }
        Rectangle { x: 0.5; y: 9.25; width: 2; height: 1.5; color: Qt.rgba(0, 0, 0, 0.6) }
        Rectangle { x: 17.5; y: 9.25; width: 2; height: 1.5; color: Qt.rgba(0, 0, 0, 0.6) }

        // Glowing Inner Accent Bezel (Hall Effect / Pro Controller ring)
        Rectangle {
          anchors.centerIn: parent
          width: 15; height: 15; radius: 7.5
          color: "transparent"
          border.color: st.on ? st.accent : (st.dispDist > 1 ? Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.65) : Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.35))
          border.width: 1.5
        }

        // 3D Concave Ergonomic Center Dish (The Thumb Bowl)
        Rectangle {
          anchors.centerIn: parent
          width: 12; height: 12; radius: 6
          color: Qt.rgba(st.accent.r * 0.16, st.accent.g * 0.16, st.accent.b * 0.16, 0.95)
          border.color: Qt.rgba(0, 0, 0, 0.60)
          border.width: 1

          // Inverted bowl shadow (top is shadowed in a concave dish!)
          Rectangle {
            x: 2; y: 1
            width: 8; height: 3; radius: 1.5
            color: Qt.rgba(0, 0, 0, 0.65)
          }

          // Inverted bowl bounce reflection (bottom catches upward light reflection!)
          Rectangle {
            x: 2; y: 8
            width: 8; height: 2.5; radius: 1.25
            color: Qt.rgba(1, 1, 1, 0.22)
          }

          // Center textured pivot core
          Rectangle {
            anchors.centerIn: parent
            width: 4; height: 4; radius: 2
            color: st.on ? st.accent : Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.65)
          }
        }
      }

      // Full-surface interactive drag mouse area
      MouseArea {
        id: stickMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: function(mouse) {
          if (root.remapMode) {
            root.requestRemap(st.side === "l" ? "stickL" : "stickR", st.stickIndex, st.side === "l" ? "LS / L3" : "RS / R3")
            return
          }
          if (mouse.button === Qt.RightButton) {
            root.setVirtualButton(st.stickIndex, !st.on)
            return
          }
          springReturnAnim.stop()
          st.isDragging = true
          var dx = mouse.x - 26
          var dy = mouse.y - 26
          var maxDist = 18.0
          var nx = dx / maxDist
          var ny = dy / maxDist
          var r = Math.sqrt(nx * nx + ny * ny)
          if (r > 1.0) {
            nx /= r
            ny /= r
          }
          st.dragX = nx
          st.dragY = ny
          root.setVirtualStick(st.side, nx, ny, true)
        }

        onPositionChanged: function(mouse) {
          if (st.isDragging) {
            var dx = mouse.x - 26
            var dy = mouse.y - 26
            var maxDist = 18.0
            var nx = dx / maxDist
            var ny = dy / maxDist
            var r = Math.sqrt(nx * nx + ny * ny)
            if (r > 1.0) {
              nx /= r
              ny /= r
            }
            st.dragX = nx
            st.dragY = ny
            root.setVirtualStick(st.side, nx, ny, true)
          }
        }

        onReleased: function(mouse) {
          if (mouse.button === Qt.RightButton) return
          springReturnAnim.restart()
        }

        onCanceled: {
          springReturnAnim.restart()
        }

        onDoubleClicked: function(mouse) {
          root.setVirtualButton(st.stickIndex, true)
          l3ReleaseTimer.restart()
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
    property bool dpadLeft: false
    property bool dpadRight: false
    property alias dpadUp: dp.up
    property alias dpadDown: dp.down
    property int idxUp: -1
    property int idxDown: -1
    property int idxLeft: -1
    property int idxRight: -1
    property color accent: root.playerColor
    readonly property bool isAny: up || down || dpadLeft || dpadRight

    // Rocker physics tilt calculations (-1..1)
    readonly property real tiltX: (dpadRight ? 1.0 : 0.0) - (dpadLeft ? 1.0 : 0.0)
    readonly property real tiltY: (down ? 1.0 : 0.0) - (up ? 1.0 : 0.0)

    x: cx - 26
    y: cy - 26
    width: 52
    height: 52

    // 1. Recessed D-Pad Crucible (Spherical Bowl in Chassis)
    Rectangle {
      anchors.centerIn: parent
      width: 50; height: 50; radius: 25
      color: Qt.rgba(0, 0, 0, 0.45)
      border.color: Qt.rgba(0, 0, 0, 0.70)
      border.width: 1

      // Top-left chamfer highlight
      Rectangle {
        x: 4; y: 2
        width: 22; height: 2; radius: 1
        color: Qt.rgba(1, 1, 1, 0.16)
      }
      // Inner shadow ring
      Rectangle {
        anchors.fill: parent; anchors.margins: 1; radius: 24
        color: "transparent"
        border.color: Qt.rgba(0, 0, 0, 0.55)
        border.width: 1.5
      }
    }

    // =========================================================================
    // XBOX SERIES 8-WAY HYBRID METALLIC DISH (Tactile 3D Rocker)
    // =========================================================================
    Item {
      id: hybridDish
      visible: root.isXbox
      anchors.centerIn: parent
      width: 44
      height: 44
      y: dp.isAny ? 5.5 : 4.0

      Behavior on y { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

      // 3D Tilting Rocker Transform
      transform: [
        Rotation {
          origin.x: 22; origin.y: 22
          axis { x: 1; y: 0; z: 0 }
          angle: -dp.tiltY * 8.5
          Behavior on angle { SpringAnimation { spring: 8.0; damping: 0.40; epsilon: 0.05 } }
        },
        Rotation {
          origin.x: 22; origin.y: 22
          axis { x: 0; y: 1; z: 0 }
          angle: dp.tiltX * 8.5
          Behavior on angle { SpringAnimation { spring: 8.0; damping: 0.40; epsilon: 0.05 } }
        }
      ]

      // Drop shadow cast by the elevated tilting dish onto the crucible floor
      Rectangle {
        x: 1 + dp.tiltX * 2.5
        y: 2.5 + dp.tiltY * 2.5
        width: 44; height: 44; radius: 22
        color: Qt.rgba(0, 0, 0, 0.65)
        z: -1
      }

      // Dish Outer Rim & Faceted Metallic Body
      Rectangle {
        id: dishRim
        anchors.fill: parent
        radius: 22
        color: Qt.darker(root.bodyColor, 1.35)
        border.color: dp.isAny ? dp.accent : Qt.rgba(root.bodyBorder.r, root.bodyBorder.g, root.bodyBorder.b, 0.55)
        border.width: dp.isAny ? 1.5 : 1.0

        // Dynamic Specular Light Shift (Crescent highlight glints towards active tilt)
        Rectangle {
          x: 6 - dp.tiltX * 3.5
          y: 3 - dp.tiltY * 3.5
          width: 32; height: 10; radius: 5
          color: Qt.rgba(1, 1, 1, dp.isAny ? 0.40 : 0.22)
          Behavior on x { NumberAnimation { duration: 40 } }
          Behavior on y { NumberAnimation { duration: 40 } }
        }

        // 8 Faceted Diagonal Creases (Visual 8-way segmentation)
        Repeater {
          model: 4
          Rectangle {
            anchors.centerIn: parent
            width: 40; height: 1
            rotation: index * 45
            color: Qt.rgba(0, 0, 0, 0.35)
          }
        }

        // Directional Neon Bloom Halo for Active Directions
        Rectangle {
          visible: dp.isAny
          anchors.centerIn: parent
          width: parent.width + 4
          height: parent.height + 4
          radius: width / 2
          color: Qt.rgba(dp.accent.r, dp.accent.g, dp.accent.b, 0.25)
          border.color: dp.accent
          border.width: 1.5
          z: -1
        }

        // 4 Raised Directional Cardinal Chevrons
        // Up Chevron
        Text {
          x: 17; y: 3
          text: "▲"
          color: dp.up ? dp.accent : (dishMouseUp.containsMouse ? Qt.lighter(root.dimGlyph, 1.3) : root.dimGlyph)
          font.pixelSize: 8
          font.bold: true
          scale: dp.up ? 1.25 : (dishMouseUp.containsMouse ? 1.15 : 1.0)
          Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
          Behavior on color { ColorAnimation { duration: 25 } }
        }
        // Down Chevron
        Text {
          x: 17; y: 31
          text: "▼"
          color: dp.down ? dp.accent : (dishMouseDown.containsMouse ? Qt.lighter(root.dimGlyph, 1.3) : root.dimGlyph)
          font.pixelSize: 8
          font.bold: true
          scale: dp.down ? 1.25 : (dishMouseDown.containsMouse ? 1.15 : 1.0)
          Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
          Behavior on color { ColorAnimation { duration: 25 } }
        }
        // Left Chevron
        Text {
          x: 4; y: 17
          text: "◀"
          color: dp.dpadLeft ? dp.accent : (dishMouseLeft.containsMouse ? Qt.lighter(root.dimGlyph, 1.3) : root.dimGlyph)
          font.pixelSize: 8
          font.bold: true
          scale: dp.dpadLeft ? 1.25 : (dishMouseLeft.containsMouse ? 1.15 : 1.0)
          Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
          Behavior on color { ColorAnimation { duration: 25 } }
        }
        // Right Chevron
        Text {
          x: 32; y: 17
          text: "▶"
          color: dp.dpadRight ? dp.accent : (dishMouseRight.containsMouse ? Qt.lighter(root.dimGlyph, 1.3) : root.dimGlyph)
          font.pixelSize: 8
          font.bold: true
          scale: dp.dpadRight ? 1.25 : (dishMouseRight.containsMouse ? 1.15 : 1.0)
          Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
          Behavior on color { ColorAnimation { duration: 25 } }
        }

        // Deep Center Concave Thumb Bowl (The Faceted Pivot Dish)
        Rectangle {
          anchors.centerIn: parent
          width: 18; height: 18; radius: 9
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: Qt.rgba(0, 0, 0, 0.70)
          border.width: 1

          // Inverted bowl shadow (top is shadowed in a concave dish)
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 1.5
            width: 12; height: 4; radius: 2
            color: Qt.rgba(0, 0, 0, 0.65)
          }

          // Inverted bowl bounce reflection (bottom catches ambient bounce)
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            width: 10; height: 3.5; radius: 1.75
            color: Qt.rgba(1, 1, 1, 0.20)
          }

          // Center Machined Pivot Pin
          Rectangle {
            anchors.centerIn: parent
            width: 5; height: 5; radius: 2.5
            color: dp.isAny ? dp.accent : Qt.rgba(root.dimGlyph.r, root.dimGlyph.g, root.dimGlyph.b, 0.50)
          }
        }
      }

      // Interactive 4-Quadrant Click Zones
      // Up Zone
      MouseArea {
        id: dishMouseUp
        x: 12; y: 0; width: 20; height: 16
        enabled: root.interactive && root.isXbox
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap("dpadUp", dp.idxUp, GamepadModel.buttonLabel(root.effectiveLayout, "dpadUp", root.profile))
            return
          }
          if (dp.idxUp >= 0) root.setVirtualButton(dp.idxUp, true)
          root.setVirtualDpad("up", true)
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            if (dp.idxUp >= 0) root.setVirtualButton(dp.idxUp, false)
            root.setVirtualDpad("up", false)
          }
        }
        onCanceled: {
          if (dp.idxUp >= 0) root.setVirtualButton(dp.idxUp, false)
          root.setVirtualDpad("up", false)
        }
      }
      // Down Zone
      MouseArea {
        id: dishMouseDown
        x: 12; y: 28; width: 20; height: 16
        enabled: root.interactive && root.isXbox
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap("dpadDown", dp.idxDown, GamepadModel.buttonLabel(root.effectiveLayout, "dpadDown", root.profile))
            return
          }
          if (dp.idxDown >= 0) root.setVirtualButton(dp.idxDown, true)
          root.setVirtualDpad("down", true)
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            if (dp.idxDown >= 0) root.setVirtualButton(dp.idxDown, false)
            root.setVirtualDpad("down", false)
          }
        }
        onCanceled: {
          if (dp.idxDown >= 0) root.setVirtualButton(dp.idxDown, false)
          root.setVirtualDpad("down", false)
        }
      }
      // Left Zone
      MouseArea {
        id: dishMouseLeft
        x: 0; y: 12; width: 16; height: 20
        enabled: root.interactive && root.isXbox
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap("dpadLeft", dp.idxLeft, GamepadModel.buttonLabel(root.effectiveLayout, "dpadLeft", root.profile))
            return
          }
          if (dp.idxLeft >= 0) root.setVirtualButton(dp.idxLeft, true)
          root.setVirtualDpad("left", true)
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            if (dp.idxLeft >= 0) root.setVirtualButton(dp.idxLeft, false)
            root.setVirtualDpad("left", false)
          }
        }
        onCanceled: {
          if (dp.idxLeft >= 0) root.setVirtualButton(dp.idxLeft, false)
          root.setVirtualDpad("left", false)
        }
      }
      // Right Zone
      MouseArea {
        id: dishMouseRight
        x: 28; y: 12; width: 16; height: 20
        enabled: root.interactive && root.isXbox
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap("dpadRight", dp.idxRight, GamepadModel.buttonLabel(root.effectiveLayout, "dpadRight", root.profile))
            return
          }
          if (dp.idxRight >= 0) root.setVirtualButton(dp.idxRight, true)
          root.setVirtualDpad("right", true)
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            if (dp.idxRight >= 0) root.setVirtualButton(dp.idxRight, false)
            root.setVirtualDpad("right", false)
          }
        }
        onCanceled: {
          if (dp.idxRight >= 0) root.setVirtualButton(dp.idxRight, false)
          root.setVirtualDpad("right", false)
        }
      }
    }

    // =========================================================================
    // CLASSIC CROSS DPAD (For PlayStation / Switch / Generic)
    // =========================================================================
    Item {
      id: classicCross
      visible: !root.isXbox
      anchors.fill: parent

      // 3D Tilting Rocker Transform for Classic Cross
      transform: [
        Rotation {
          origin.x: 26; origin.y: 26
          axis { x: 1; y: 0; z: 0 }
          angle: -dp.tiltY * 7.5
          Behavior on angle { SpringAnimation { spring: 8.0; damping: 0.40; epsilon: 0.05 } }
        },
        Rotation {
          origin.x: 26; origin.y: 26
          axis { x: 0; y: 1; z: 0 }
          angle: dp.tiltX * 7.5
          Behavior on angle { SpringAnimation { spring: 8.0; damping: 0.40; epsilon: 0.05 } }
        }
      ]

      // 2. Extruded 3D Cross Base Sidewall (2px shadow under cross)
      Rectangle {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2
        width: 16; height: 44; radius: 4
        color: Qt.rgba(0, 0, 0, 0.55)
      }
      Rectangle {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2
        width: 44; height: 16; radius: 4
        color: Qt.rgba(0, 0, 0, 0.55)
      }

      // 3. Main Cross Surface
      Rectangle {
        anchors.centerIn: parent
        width: 16; height: 44; radius: 4
        color: root.idleFill
        border.color: root.bodyBorder
        border.width: 1
      }
      Rectangle {
        anchors.centerIn: parent
        width: 44; height: 16; radius: 4
        color: root.idleFill
        border.color: root.bodyBorder
        border.width: 1
      }

      // 4. Directional Arms with 3D Facets & Tactile Rocker Motion
      DpadArm { dir: "up";    on: dp.up;        buttonIndex: dp.idxUp;    accent: dp.accent }
      DpadArm { dir: "down";  on: dp.down;      buttonIndex: dp.idxDown;  accent: dp.accent }
      DpadArm { dir: "left";  on: dp.dpadLeft;  buttonIndex: dp.idxLeft;  accent: dp.accent }
      DpadArm { dir: "right"; on: dp.dpadRight; buttonIndex: dp.idxRight; accent: dp.accent }

      // 5. Ergonomic Center Pivot Dish (Concave Thumb Bowl)
      Rectangle {
        anchors.centerIn: parent
        width: 14; height: 14; radius: 7
        color: Qt.rgba(0, 0, 0, 0.35)
        border.color: Qt.rgba(0, 0, 0, 0.60)
        border.width: 1

        // Inverted bowl bottom bounce reflection
        Rectangle {
          x: 3; y: 9
          width: 8; height: 2; radius: 1
          color: Qt.rgba(1, 1, 1, 0.20)
        }

        // Center pivot pin
        Rectangle {
          anchors.centerIn: parent
          width: 4; height: 4; radius: 2
          color: Qt.rgba(root.dimGlyph.r, root.dimGlyph.g, root.dimGlyph.b, 0.40)
        }
      }
    }
  }

  // ------------------------------------------------------------- DpadArm
  component DpadArm : Rectangle {
    id: dpadArmItem
    property string dir: "up"
    property string role: dir === "up" ? "dpadUp" : dir === "down" ? "dpadDown" : dir === "left" ? "dpadLeft" : "dpadRight"
    property string label: GamepadModel.buttonLabel(root.effectiveLayout, role, root.profile)
    property bool on: false
    property int buttonIndex: -1
    property color accent: root.playerColor
    width: 16
    height: 16
    radius: 3
    // Tactile rocker switch tilt: depresses 1.5px toward center when clicked
    x: dir === "left" ? (on ? 5.5 : 4) : dir === "right" ? (on ? 30.5 : 32) : 18
    y: dir === "up" ? (on ? 5.5 : 4) : dir === "down" ? (on ? 30.5 : 32) : 18

    rotation: 0
    color: on ? dpadArmItem.accent : (dir === "up" ? Qt.rgba(1, 1, 1, 0.08) : dir === "down" ? Qt.rgba(0, 0, 0, 0.20) : "transparent")
    border.color: on ? dpadArmItem.accent : (dpadMouse.containsMouse ? Qt.rgba(dpadArmItem.accent.r, dpadArmItem.accent.g, dpadArmItem.accent.b, 0.50) : "transparent")
    border.width: on ? 2 : (dpadMouse.containsMouse ? 1 : 0)
    scale: on ? 0.94 : (dpadMouse.containsMouse ? 1.08 : 1.0)

    Behavior on y { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
    Behavior on x { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
    Behavior on color { ColorAnimation { duration: 25 } }
    Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

    MouseArea {
      id: dpadMouse
      anchors.fill: parent
      enabled: root.interactive
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton || root.remapMode) {
          root.requestRemap(dpadArmItem.role, dpadArmItem.buttonIndex, dpadArmItem.label)
          return
        }
        if (dpadArmItem.buttonIndex >= 0) root.setVirtualButton(dpadArmItem.buttonIndex, true)
        root.setVirtualDpad(dpadArmItem.dir, true)
      }
      onReleased: function(mouse) {
        if (mouse.button === Qt.LeftButton && !root.remapMode) {
          if (dpadArmItem.buttonIndex >= 0) root.setVirtualButton(dpadArmItem.buttonIndex, false)
          root.setVirtualDpad(dpadArmItem.dir, false)
        }
      }
      onCanceled: {
        if (dpadArmItem.buttonIndex >= 0) root.setVirtualButton(dpadArmItem.buttonIndex, false)
        root.setVirtualDpad(dpadArmItem.dir, false)
      }
    }

    // Glow halo
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 6
      height: parent.height + 6
      radius: 5
      color: Qt.rgba(dpadArmItem.accent.r, dpadArmItem.accent.g, dpadArmItem.accent.b, dpadArmItem.on ? 0.35 : 0)
      border.color: Qt.rgba(dpadArmItem.accent.r, dpadArmItem.accent.g, dpadArmItem.accent.b, dpadArmItem.on ? 0.75 : 0)
      border.width: 2
      opacity: (dpadArmItem.on || dpadMouse.containsMouse) ? 1.0 : 0.0
      z: -1
      Behavior on opacity { NumberAnimation { duration: 50 } }
    }

    // 3D Beveled Top Edge on Up Arm
    Rectangle {
      visible: dpadArmItem.dir === "up" && !dpadArmItem.on
      x: 1; y: 1; width: parent.width - 2; height: 2; radius: 1
      color: Qt.rgba(1, 1, 1, 0.24)
    }

    // 3D Shadow Bottom Edge on Down Arm
    Rectangle {
      visible: dpadArmItem.dir === "down" && !dpadArmItem.on
      x: 1; y: parent.height - 2; width: parent.width - 2; height: 1.5; radius: 0.75
      color: Qt.rgba(0, 0, 0, 0.45)
    }

    // 3D Highlight Left Edge on Left Arm
    Rectangle {
      visible: dpadArmItem.dir === "left" && !dpadArmItem.on
      x: 1; y: 1; width: 2; height: parent.height - 2; radius: 1
      color: Qt.rgba(1, 1, 1, 0.16)
    }

    // 3D Shadow Right Edge on Right Arm
    Rectangle {
      visible: dpadArmItem.dir === "right" && !dpadArmItem.on
      x: parent.width - 2; y: 1; width: 1.5; height: parent.height - 2; radius: 0.75
      color: Qt.rgba(0, 0, 0, 0.40)
    }

    // Embossed Tactile Chevron Shadow
    Text {
      visible: root.showLabels
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 1
      text: dpadArmItem.dir === "up" ? "▲" : dpadArmItem.dir === "down" ? "▼" : dpadArmItem.dir === "left" ? "◀" : "▶"
      color: Qt.rgba(0, 0, 0, 0.60)
      font.pixelSize: 8
      font.bold: true
      font.family: Style.font.family
    }

    // Directional chevron indicator
    Text {
      visible: root.showLabels
      anchors.centerIn: parent
      text: dpadArmItem.dir === "up" ? "▲" : dpadArmItem.dir === "down" ? "▼" : dpadArmItem.dir === "left" ? "◀" : "▶"
      color: dpadArmItem.on ? Color.popups.background : root.glyphColor
      font.pixelSize: 8
      font.bold: true
      font.family: Style.font.family
    }
  }

  // ---------------------------------------------------------- FaceButton
  // Pressable 3D domed acrylic gem button. Bored shell socket well, extruded
  // cylindrical sidewall, glossy specular crescent sheen, and tactile depression.
  component FaceButton : Item {
    id: fb
    property real cx: 0
    property real cy: 0
    property string label: ""
    property string pos: "bottom"
    property string role: pos === "top" ? "faceTop" : pos === "bottom" ? "faceBottom" : pos === "left" ? "faceLeft" : "faceRight"
    property string artSource: ""
    property bool on: false
    property int buttonIndex: -1

    // Theme-Reactive Accent (Omarchy Active Accent Color)
    readonly property color buttonAccent: {
      if (root.isXbox) {
        return root.playerColor
      }
      if (root.isSwitch) {
        if (fb.pos === "top") return "#FBBF24"    // X - warm amber
        if (fb.pos === "bottom") return "#34D399" // B - mint green
        if (fb.pos === "left") return "#38BDF8"   // Y - cyan azure
        if (fb.pos === "right") return "#F43F5E"  // A - coral rose
      }
      if (root.isPs) {
        if (fb.pos === "top") return "#40E2A0"    // △ - emerald
        if (fb.pos === "bottom") return "#A78BFA" // × - lavender
        if (fb.pos === "left") return "#F472B6"   // □ - pink
        if (fb.pos === "right") return "#F87171"  // ○ - coral crimson
      }
      return root.playerColor
    }

    x: cx - 14
    y: cy - 14
    width: 28
    height: 28

    // 1. Bored Cylindrical Shell Socket Well
    Rectangle {
      anchors.centerIn: parent
      width: 28; height: 28; radius: 14
      color: Qt.rgba(0, 0, 0, 0.50)
      border.color: Qt.rgba(0, 0, 0, 0.70)
      border.width: 1

      // Top chamfer reflection on the chassis hole
      Rectangle {
        x: 4; y: 1
        width: 14; height: 1.5; radius: 0.75
        color: Qt.rgba(1, 1, 1, 0.12)
      }
    }

    // 2. Extruded 3D Button Cylinder (Sidewall Base)
    // Protrudes 2.5px above the shell when idle.
    Rectangle {
      visible: !fb.on
      anchors.horizontalCenter: parent.horizontalCenter
      y: 4.5
      width: 24; height: 24; radius: 12
      color: Qt.darker(fb.buttonAccent, 2.0)
      border.color: Qt.rgba(0, 0, 0, 0.75)
      border.width: 1

      // Bottom shadow lip
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 18; height: 3; radius: 1.5
        color: Qt.rgba(0, 0, 0, 0.65)
      }
    }

    // 3. 3D Domed Acrylic Gem Button Cap
    Item {
      id: capItem
      anchors.horizontalCenter: parent.horizontalCenter
      // Mechanical tactile stroke: sinks 2px down into socket when pressed!
      y: fb.on ? 4.0 : 2.0
      width: 24
      height: 24
      scale: fb.on ? 0.94 : (fbMouse.containsMouse ? 1.06 : 1.0)

      Behavior on y { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
      Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

      MouseArea {
        id: fbMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            root.requestRemap(fb.role, fb.buttonIndex, fb.label)
            return
          }
          root.setVirtualButton(fb.buttonIndex, true)
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            root.setVirtualButton(fb.buttonIndex, false)
          }
        }
        onCanceled: root.setVirtualButton(fb.buttonIndex, false)
      }

      // Glow halo bloom on press or hover
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 8
        height: parent.height + 8
        radius: width / 2
        color: Qt.rgba(fb.buttonAccent.r, fb.buttonAccent.g, fb.buttonAccent.b, fb.on ? 0.40 : 0)
        border.color: Qt.rgba(fb.buttonAccent.r, fb.buttonAccent.g, fb.buttonAccent.b, fb.on ? 0.85 : 0.45)
        border.width: fb.on ? 2 : 1
        opacity: (fb.on || fbMouse.containsMouse) ? 1.0 : 0.0
        z: -1
        Behavior on opacity { NumberAnimation { duration: 50 } }
      }

      // Acrylic button dome surface
      Rectangle {
        anchors.fill: parent
        radius: 12
        color: fb.on
          ? (root.isXbox ? root.playerColor : Qt.lighter(fb.buttonAccent, 1.15))
          : (fbMouse.containsMouse
              ? Qt.rgba(fb.buttonAccent.r, fb.buttonAccent.g, fb.buttonAccent.b, 0.35)
              : Qt.rgba(0.12, 0.14, 0.18, 0.95))
        border.color: fb.on
          ? "#FFFFFF"
          : (fbMouse.containsMouse ? fb.buttonAccent : Qt.rgba(fb.buttonAccent.r, fb.buttonAccent.g, fb.buttonAccent.b, 0.65))
        border.width: fb.on ? 1.8 : 1.2

        // Glossy 3D Acrylic Specular Crescent Highlight (The glass dome reflection)
        Rectangle {
          x: 3; y: 1.5
          width: 18; height: 8; radius: 4
          color: Qt.rgba(1, 1, 1, 0.46)
        }

        // Secondary tight specular point reflection
        Rectangle {
          x: 6; y: 2.5
          width: 5; height: 2; radius: 1
          color: Qt.rgba(1, 1, 1, 0.70)
        }

        // Lower internal refraction caustics highlight
        Rectangle {
          x: 5; y: 16
          width: 14; height: 5; radius: 2.5
          color: Qt.rgba(1, 1, 1, 0.16)
        }

        // SVG Cap Art (Clean Vector Button Glyph)
        Image {
          id: faceCapImg
          visible: fb.artSource !== "" && status === Image.Ready
          anchors.fill: parent
          anchors.margins: 1.5
          source: fb.artSource
          fillMode: Image.PreserveAspectFit
          mipmap: true
          smooth: true
          layer.enabled: visible
          layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: fb.on
              ? (root.isXbox ? Color.popups.background : (root.isPs ? Color.popups.background : "#FFFFFF"))
              : (root.isXbox ? root.playerColor : (root.isPs ? fb.buttonAccent : root.glyphColor))
          }
        }

        // 3D Engraved Drop Shadow for Button Glyph
        Text {
          visible: root.showLabels && (!faceCapImg.visible || faceCapImg.status !== Image.Ready)
          anchors.centerIn: parent
          anchors.verticalCenterOffset: 1
          text: fb.label
          color: Qt.rgba(0, 0, 0, 0.65)
          font.pixelSize: root.isPs ? 13 : 11
          font.bold: true
          font.family: Style.font.family
        }

        // Crisp 3D Button Glyph / Letter (Pure white on Switch, theme-reactive on Xbox, vibrant on PlayStation)
        Text {
          visible: root.showLabels && (!faceCapImg.visible || faceCapImg.status !== Image.Ready)
          anchors.centerIn: parent
          text: fb.label
          color: fb.on
            ? (root.isXbox ? Color.popups.background : (root.isPs ? Color.popups.background : "#000000"))
            : (root.isXbox ? root.playerColor : fb.buttonAccent)
          font.pixelSize: root.isPs ? 13 : 11
          font.bold: true
          font.family: Style.font.family
        }
      }
    }
  }

  // ----------------------------------------------------------- CircleKey
  // ----------------------------------------------------------- CircleKey
  component CircleKey : Item {
    id: ck
    property real cx: 0
    property real cy: 0
    property real r: 8
    property string label: ""
    property string role: ""
    property string artSource: ""
    property bool on: false
    property int buttonIndex: -1
    property color accent: root.playerColor
    property bool showLabel: true
    property int labelSize: 7
    readonly property bool isXboxGuide: root.isXbox && (ck.role === "centerTop" || ck.label === "XBOX" || ck.label === "Xbox")

    x: cx - r - 1
    y: cy - r - 1
    width: (r + 1) * 2
    height: (r + 1) * 2

    // 1. Bored socket well in chassis
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.45)
      border.color: Qt.rgba(0, 0, 0, 0.65)
      border.width: 1
    }

    // 2. Extruded cylinder sidewall base
    Rectangle {
      visible: !ck.on
      anchors.horizontalCenter: parent.horizontalCenter
      y: 2.5
      width: ck.r * 2
      height: ck.r * 2
      radius: ck.r
      color: Qt.rgba(0, 0, 0, 0.60)
    }

    // 3. Domed Key Cap (With Xbox Nexus Jewel Styling)
    Rectangle {
      id: keyCap
      anchors.horizontalCenter: parent.horizontalCenter
      // Tactile click depression: sinks 1.5px into socket when pressed
      y: ck.on ? 2.5 : 1.0
      width: ck.r * 2
      height: ck.r * 2
      radius: ck.r
      color: ck.on
        ? (ck.isXboxGuide ? Qt.lighter(ck.accent, 1.25) : ck.accent)
        : (ck.isXboxGuide
            ? (ckMouse.containsMouse ? Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, 0.25) : Qt.rgba(0.08, 0.10, 0.14, 0.95))
            : (ckMouse.containsMouse ? Qt.lighter(root.idleFill, 1.20) : root.idleFill))
      border.color: ck.on
        ? "#FFFFFF"
        : (ck.isXboxGuide
            ? (ckMouse.containsMouse ? ck.accent : Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, 0.65))
            : (ckMouse.containsMouse ? Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, 0.60) : root.bodyBorder))
      border.width: ck.on ? 2 : (ck.isXboxGuide ? 1.5 : 1)
      scale: ck.on ? 0.94 : (ckMouse.containsMouse ? 1.08 : 1.0)

      Behavior on y { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
      Behavior on color { ColorAnimation { duration: 25 } }
      Behavior on scale { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }

      MouseArea {
        id: ckMouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton || root.remapMode) {
            if (ck.role !== "") {
              root.requestRemap(ck.role, ck.buttonIndex, ck.label)
              return
            }
          }
          root.setVirtualButton(ck.buttonIndex, true)
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.LeftButton && !root.remapMode) {
            root.setVirtualButton(ck.buttonIndex, false)
          }
        }
        onCanceled: root.setVirtualButton(ck.buttonIndex, false)
      }

      // Glow halo (Nexus ambient breathing LED glow when Xbox Guide)
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + 6
        height: parent.height + 6
        radius: width / 2
        color: Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, ck.on ? 0.45 : (ck.isXboxGuide ? 0.22 : 0))
        border.color: Qt.rgba(ck.accent.r, ck.accent.g, ck.accent.b, ck.on ? 0.85 : 0.55)
        border.width: 1.5
        opacity: (ck.on || ckMouse.containsMouse || ck.isXboxGuide) ? 1.0 : 0.0
        z: -1
        Behavior on opacity { NumberAnimation { duration: 50 } }
      }

      // Top specular highlight sheen
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 1
        width: Math.max(4, parent.width - 4)
        height: Math.max(2, parent.height * 0.4)
        radius: width / 2
        color: Qt.rgba(1, 1, 1, ck.on ? 0.45 : (ck.isXboxGuide ? 0.32 : 0.18))
      }

      // Vector cap art (View, Menu, Share, Guide)
      Image {
        id: ckSvgImg
        visible: ck.artSource !== "" && status === Image.Ready
        anchors.fill: parent
        anchors.margins: ck.isXboxGuide ? 2.5 : (ck.r >= 7 ? 1.5 : 1)
        source: ck.artSource
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        layer.enabled: visible
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: ck.on
            ? (ck.isXboxGuide ? Color.popups.background : Color.popups.background)
            : (ck.isXboxGuide ? "#FFFFFF" : (ckMouse.containsMouse ? ck.accent : root.glyphColor))
        }
      }

      // Embossed shadow for text label
      Text {
        visible: (!ckSvgImg.visible || ckSvgImg.status !== Image.Ready) && ck.showLabel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: ck.label
        color: Qt.rgba(0, 0, 0, 0.50)
        font.pixelSize: ck.labelSize
        font.bold: true
        font.family: Style.font.family
      }

      // Core text label
      Text {
        visible: (!ckSvgImg.visible || ckSvgImg.status !== Image.Ready) && ck.showLabel
        anchors.centerIn: parent
        text: ck.label
        color: ck.on ? Color.popups.background : root.glyphColor
        font.pixelSize: ck.labelSize
        font.bold: true
        font.family: Style.font.family
      }
    }
  }
}
