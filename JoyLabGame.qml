import QtQuick
import qs.Commons
import qs.Ui
import "GamepadModel.js" as GamepadModel

// omycontroller — JoyLabGame.qml
//
// 60 FPS Retro Mario-style Platformer Benchmark Arena.
// Evaluates real hardware stick linearity, variable jump actuation latency,
// spring snapback, and tactile haptic feedback under live gameplay conditions.

Item {
  id: root
  implicitWidth: Style.space(640)
  implicitHeight: Style.space(380)
  clip: true

  // Input bindings from deck
  property var liveButtons: ({})
  property var liveAxes: []
  property var axisMap: ({ lx: 0, ly: 1, rx: 2, ry: 3, lt: -1, rt: -1, hatX: -1, hatY: -1 })
  property string layout: "generic"
  property color playerColor: Color.accent
  property color foregroundColor: Style.color.foreground

  // Output signals
  signal runCompleted(var telemetry)
  signal requestRumble(real weak, real strong, int ms)

  // ------------------------------------------------------------ Telemetry state
  property real currentStickError: 0.0
  property real avgStickError: 7.2
  property int stickSamples: 0
  property real sumStickError: 0.0

  property int snapbackCount: 0
  property real lastStickX: 0.0
  property real lastStickTime: 0.0

  property int jumpCount: 0
  property int coinCount: 0
  property int totalActuations: 0
  property real runStartTime: 0
  property bool runActive: false
  property bool runFinished: false

  // ------------------------------------------------------------ Input Processing
  readonly property real stickX: {
    if (!root.liveAxes || root.liveAxes.length === 0) return 0.0
    var idx = root.axisMap && root.axisMap.lx !== undefined ? root.axisMap.lx : 0
    var val = Number(root.liveAxes[idx]) || 0.0
    return Math.abs(val) > 0.08 ? val : 0.0
  }

  readonly property real stickY: {
    if (!root.liveAxes || root.liveAxes.length === 0) return 0.0
    var idx = root.axisMap && root.axisMap.ly !== undefined ? root.axisMap.ly : 1
    var val = Number(root.liveAxes[idx]) || 0.0
    return Math.abs(val) > 0.08 ? val : 0.0
  }

  readonly property var buttonTables: GamepadModel.buttonTables(root.layout)

  readonly property bool jumpPressed: {
    if (!root.liveButtons) return false
    var btnIdx = root.buttonTables.faceBottom
    return !!root.liveButtons[btnIdx]
  }

  readonly property bool dashPressed: {
    if (!root.liveButtons) return false
    var btnRight = root.buttonTables.faceRight
    var btnLeft = root.buttonTables.faceLeft
    var rtIdx = root.axisMap && root.axisMap.rt !== undefined ? root.axisMap.rt : -1
    var rtVal = (rtIdx >= 0 && root.liveAxes && root.liveAxes.length > rtIdx) ? Number(root.liveAxes[rtIdx]) : -1.0
    return !!root.liveButtons[btnRight] || !!root.liveButtons[btnLeft] || rtVal > 0.3
  }

  readonly property bool dpadLeft: {
    return GamepadModel.isDpadActive("left", root.liveButtons, root.liveAxes, root.buttonTables, root.axisMap)
  }

  readonly property bool dpadRight: {
    return GamepadModel.isDpadActive("right", root.liveButtons, root.liveAxes, root.buttonTables, root.axisMap)
  }

  // ------------------------------------------------------------ Physics & Entities
  readonly property real arenaWidth: 2600
  readonly property real arenaHeight: root.height
  readonly property real groundY: arenaHeight - Style.space(48)

  property real cameraX: 0
  property real playerX: Style.space(60)
  property real playerY: groundY - Style.space(32)
  property real playerVx: 0.0
  property real playerVy: 0.0
  property bool isGrounded: true
  property bool isJumping: false
  property int jumpHoldFrames: 0
  property bool facingRight: true
  property real runCycle: 0.0

  // Platforms & Blocks (X, Y, Width, Height, Type, Hit)
  // Types: "ground", "pipe", "block", "brick", "flag"
  property var blocks: [
    { x: 260, y: groundY - 85,  w: 36, h: 36, type: "block", hit: false, coinAnim: 0 },
    { x: 320, y: groundY - 85,  w: 36, h: 36, type: "brick", hit: false, coinAnim: 0 },
    { x: 380, y: groundY - 85,  w: 36, h: 36, type: "block", hit: false, coinAnim: 0 },
    { x: 440, y: groundY - 85,  w: 36, h: 36, type: "brick", hit: false, coinAnim: 0 },
    { x: 580, y: groundY - 50,  w: 48, h: 50, type: "pipe",  hit: false, coinAnim: 0 },
    { x: 740, y: groundY - 95,  w: 36, h: 36, type: "block", hit: false, coinAnim: 0 },
    { x: 860, y: groundY - 70,  w: 52, h: 70, type: "pipe",  hit: false, coinAnim: 0 },
    { x: 1040, y: groundY - 90, w: 140, h: 24, type: "bridge", hit: false, coinAnim: 0 },
    { x: 1240, y: groundY - 110, w: 36, h: 36, type: "block", hit: false, coinAnim: 0 },
    { x: 1300, y: groundY - 110, w: 36, h: 36, type: "block", hit: false, coinAnim: 0 },
    { x: 1440, y: groundY - 80,  w: 54, h: 80, type: "pipe",  hit: false, coinAnim: 0 },
    { x: 1640, y: groundY - 95,  w: 160, h: 24, type: "bridge", hit: false, coinAnim: 0 },
    { x: 1900, y: groundY - 60,  w: 54, h: 60, type: "pipe",  hit: false, coinAnim: 0 },
    { x: 2150, y: groundY - 120, w: 36, h: 36, type: "block", hit: false, coinAnim: 0 },
    { x: 2320, y: groundY - 180, w: 30, h: 180, type: "flag", hit: false, coinAnim: 0 }
  ]

  // Track jump press transition for actuation counting
  property bool wasJumpPressed: false

  function resetGame() {
    playerX = Style.space(60)
    playerY = groundY - Style.space(32)
    playerVx = 0
    playerVy = 0
    isGrounded = true
    isJumping = false
    cameraX = 0
    coinCount = 0
    jumpCount = 0
    snapbackCount = 0
    sumStickError = 0
    stickSamples = 0
    avgStickError = 7.2
    runStartTime = Date.now()
    runActive = true
    runFinished = false

    for (var i = 0; i < blocks.length; i++) {
      blocks[i].hit = false
      blocks[i].coinAnim = 0
    }
  }

  Component.onCompleted: resetGame()

  // ------------------------------------------------------------ 60 FPS Game Loop
  Timer {
    id: gameLoop
    interval: 16
    running: true
    repeat: true
    onTriggered: root.updatePhysics()
  }

  function updatePhysics() {
    var now = Date.now()
    var sx = root.stickX
    var sy = root.stickY

    // 1. Digital or analog horizontal intent
    var moveIntent = sx
    if (root.dpadLeft) moveIntent = -1.0
    else if (root.dpadRight) moveIntent = 1.0

    // 2. Measure instantaneous Stick Circularity Error during active tilt
    var mag = Math.hypot(sx, sy)
    if (mag > 0.35) {
      var err = Math.abs(mag - 1.0) * 100
      root.currentStickError = err
      root.sumStickError += err
      root.stickSamples++
      root.avgStickError = Math.round((root.sumStickError / root.stickSamples) * 10) / 10
    }

    // 3. Snapback detection: stick quickly crossing 0 with opposite sign
    if (Math.abs(root.lastStickX) > 0.6 && Math.abs(sx) < 0.15) {
      root.lastStickTime = now
    } else if (now - root.lastStickTime < 75 && root.lastStickTime > 0) {
      if ((root.lastStickX > 0.5 && sx < -0.22) || (root.lastStickX < -0.5 && sx > 0.22)) {
        root.snapbackCount++
        root.lastStickTime = 0
      }
    }
    root.lastStickX = sx

    // 4. Horizontal velocity & Acceleration
    var maxSpeed = root.dashPressed ? 7.8 : 4.6
    var targetVx = moveIntent * maxSpeed
    root.playerVx += (targetVx - root.playerVx) * 0.24

    if (Math.abs(root.playerVx) > 0.2) {
      root.facingRight = root.playerVx > 0
      root.runCycle += Math.abs(root.playerVx) * 0.18
    } else {
      root.runCycle = 0
    }

    // 5. Jump logic with variable jump height
    var jPressed = root.jumpPressed
    if (jPressed && !root.wasJumpPressed && root.isGrounded) {
      // Jump initiation impulse
      root.playerVy = -9.8
      root.isGrounded = false
      root.isJumping = true
      root.jumpHoldFrames = 0
      root.jumpCount++
      root.totalActuations++
    } else if (jPressed && root.isJumping && root.jumpHoldFrames < 12) {
      // Holding jump button applies sustained upward thrust
      root.playerVy -= 0.35
      root.jumpHoldFrames++
    } else {
      root.isJumping = false
    }
    root.wasJumpPressed = jPressed

    // 6. Gravity & Vertical integration
    root.playerVy += 0.62 // gravity
    if (root.playerVy > 12.0) root.playerVy = 12.0 // terminal velocity

    var nextX = root.playerX + root.playerVx
    var nextY = root.playerY + root.playerVy

    // 7. Collision Detection
    var pWidth = 24
    var pHeight = 32
    var groundedThisFrame = false

    // Ground collision
    if (nextY + pHeight >= root.groundY) {
      nextY = root.groundY - pHeight
      if (root.playerVy > 8.0) {
        root.requestRumble(0.25, 0.45, 70) // Ground landing thud
      }
      root.playerVy = 0
      groundedThisFrame = true
    }

    // Obstacles and Blocks collision
    for (var i = 0; i < root.blocks.length; i++) {
      var b = root.blocks[i]

      // Flagpole collision check
      if (b.type === "flag") {
        if (nextX + pWidth >= b.x && root.playerX <= b.x + b.w) {
          if (!root.runFinished) {
            root.runFinished = true
            b.hit = true
            root.requestRumble(0.75, 0.55, 450)
            var elapsedSec = Math.max(1, Math.round((now - root.runStartTime) / 100) / 10)
            root.runCompleted({
              stickError: root.avgStickError,
              snapbacks: root.snapbackCount,
              jumps: root.jumpCount,
              coins: root.coinCount,
              actuations: root.totalActuations,
              timeSec: elapsedSec
            })
          }
        }
        continue
      }

      // Block AABB collision
      var hitX = (nextX + pWidth > b.x && nextX < b.x + b.w)
      var hitY = (nextY + pHeight > b.y && nextY < b.y + b.h)

      if (hitX && hitY) {
        // Hitting block from below
        if (root.playerY >= b.y + b.h - 8 && root.playerVy < 0) {
          nextY = b.y + b.h
          root.playerVy = 1.0
          if (!b.hit && (b.type === "block" || b.type === "brick")) {
            b.hit = true
            b.coinAnim = 1.0
            root.coinCount++
            root.totalActuations++
            root.requestRumble(0.35, 0.15, 60) // Crisp coin tick!
          }
        }
        // Landing on block from above
        else if (root.playerY + pHeight <= b.y + 10 && root.playerVy > 0) {
          nextY = b.y - pHeight
          root.playerVy = 0
          groundedThisFrame = true
        }
        // Side collision (Pipes / Walls)
        else {
          if (root.playerVx > 0) nextX = b.x - pWidth
          else if (root.playerVx < 0) nextX = b.x + b.w
          root.playerVx = 0
        }
      }

      // Animate hit coin popping out
      if (b.coinAnim > 0) {
        b.coinAnim = Math.max(0, b.coinAnim - 0.04)
      }
    }

    root.isGrounded = groundedThisFrame
    root.playerX = Math.max(0, Math.min(root.arenaWidth - pWidth, nextX))
    root.playerY = nextY

    // Smooth Camera lerp
    var targetCam = root.playerX - (root.width * 0.40)
    targetCam = Math.max(0, Math.min(root.arenaWidth - root.width, targetCam))
    root.cameraX += (targetCam - root.cameraX) * 0.16
  }

  // ------------------------------------------------------------ Visual Presentation
  Rectangle {
    anchors.fill: parent
    color: "#0b0f19" // deep dark retro sky

    // Distant stars / pixel clouds
    Repeater {
      model: 16
      Rectangle {
        x: (index * 173) % root.width
        y: 20 + ((index * 47) % 120)
        width: 3 + (index % 3) * 2
        height: width
        radius: 1
        color: Qt.rgba(1, 1, 1, 0.25)
      }
    }

    // World Items Container (Shifted by cameraX)
    Item {
      id: worldContainer
      x: -root.cameraX
      y: 0
      width: root.arenaWidth
      height: parent.height

      // Floor Bricks
      Rectangle {
        x: 0
        y: root.groundY
        width: root.arenaWidth
        height: root.height - root.groundY
        color: "#1e293b"
        border.color: Qt.rgba(0.2, 0.8, 0.5, 0.6)
        border.width: 2

        // Retro brick grid pattern
        Row {
          spacing: 24
          Repeater {
            model: Math.ceil(root.arenaWidth / 24)
            Rectangle {
              width: 1
              height: parent.height
              color: Qt.rgba(0.2, 0.8, 0.5, 0.15)
            }
          }
        }
      }

      // Blocks & Obstacles
      Repeater {
        model: root.blocks
        Item {
          required property var modelData
          x: modelData.x
          y: modelData.y
          width: modelData.w
          height: modelData.h

          // Pipe obstacle
          Rectangle {
            visible: modelData.type === "pipe"
            anchors.fill: parent
            color: "#15803d" // retro pipe green
            radius: 4
            border.color: "#22c55e"
            border.width: 2

            // Pipe rim
            Rectangle {
              anchors.top: parent.top
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width + 6
              height: 12
              color: "#16a34a"
              radius: 3
              border.color: "#4ade80"
              border.width: 1.5
            }
          }

          // Question mark coin block
          Rectangle {
            visible: modelData.type === "block"
            anchors.fill: parent
            radius: 4
            color: modelData.hit ? "#475569" : "#d97706"
            border.color: modelData.hit ? "#334155" : "#f59e0b"
            border.width: 2

            Text {
              anchors.centerIn: parent
              text: modelData.hit ? "•" : "?"
              color: modelData.hit ? "#94a3b8" : "#fef3c7"
              font.bold: true
              font.pixelSize: 18
            }

            // Popping coin animation
            Item {
              visible: modelData.coinAnim > 0
              anchors.horizontalCenter: parent.horizontalCenter
              y: -30 * (1.0 - modelData.coinAnim * 0.5)
              opacity: modelData.coinAnim

              Rectangle {
                anchors.centerIn: parent
                width: 16
                height: 20
                radius: 8
                color: "#fbbf24"
                border.color: "#fef08a"
                border.width: 1.5

                Text {
                  anchors.centerIn: parent
                  text: "$"
                  font.pixelSize: 11
                  font.bold: true
                  color: "#78350f"
                }
              }
            }
          }

          // Brick block
          Rectangle {
            visible: modelData.type === "brick"
            anchors.fill: parent
            radius: 3
            color: modelData.hit ? "#334155" : "#991b1b"
            border.color: modelData.hit ? "#1e293b" : "#dc2626"
            border.width: 1.5
          }

          // Bridge platform
          Rectangle {
            visible: modelData.type === "bridge"
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.35)
            border.color: root.playerColor
            border.width: 1.5
          }

          // Flagpole
          Item {
            visible: modelData.type === "flag"
            anchors.fill: parent

            // Pole
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 5
              color: "#cbd5e1"
              radius: 2
            }

            // Ball top
            Rectangle {
              anchors.top: parent.top
              anchors.horizontalCenter: parent.horizontalCenter
              width: 14
              height: 14
              radius: 7
              color: "#f59e0b"
            }

            // Flag banner
            Rectangle {
              x: 12
              y: modelData.hit ? parent.height - 35 : 12
              width: 30
              height: 22
              color: root.playerColor
              radius: 2
              Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutBounce } }

              Text {
                anchors.centerIn: parent
                text: "★"
                color: "#ffffff"
                font.bold: true
              }
            }
          }
        }
      }

      // Player Character (Mario Retro Style)
      Item {
        id: playerSprite
        x: root.playerX
        y: root.playerY
        width: 24
        height: 32

        // Cap / Hat
        Rectangle {
          x: root.facingRight ? 4 : 0
          y: 0
          width: 18
          height: 8
          radius: 3
          color: root.playerColor
        }

        // Face & Mustache
        Rectangle {
          x: root.facingRight ? 6 : 2
          y: 6
          width: 14
          height: 10
          radius: 2
          color: "#fcd34d" // skin tone

          // Eye
          Rectangle {
            x: root.facingRight ? 9 : 2
            y: 2
            width: 3
            height: 3
            color: "#0f172a"
          }

          // Mustache
          Rectangle {
            x: root.facingRight ? 7 : 1
            y: 6
            width: 7
            height: 3
            color: "#78350f"
          }
        }

        // Overalls Body
        Rectangle {
          x: 4
          y: 15
          width: 16
          height: 12
          radius: 3
          color: "#2563eb" // denim blue

          // Buttons
          Rectangle {
            x: 3; y: 2; width: 3; height: 3; radius: 1.5; color: "#fbbf24"
          }
          Rectangle {
            x: 10; y: 2; width: 3; height: 3; radius: 1.5; color: "#fbbf24"
          }
        }

        // Feet / Shoes (animated with runCycle)
        Rectangle {
          x: root.facingRight ? (1 + Math.sin(root.runCycle) * 3) : (1 - Math.sin(root.runCycle) * 3)
          y: 27
          width: 9
          height: 5
          radius: 2
          color: "#78350f"
        }
        Rectangle {
          x: root.facingRight ? (12 - Math.sin(root.runCycle) * 3) : (12 + Math.sin(root.runCycle) * 3)
          y: 27
          width: 9
          height: 5
          radius: 2
          color: "#78350f"
        }
      }
    }

    // ------------------------------------------------------------ Floating Telemetry HUD
    Rectangle {
      anchors.top: parent.top
      anchors.topMargin: Style.space(8)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(24)
      height: Style.space(34)
      radius: Math.max(6, Style.cornerRadius)
      color: Qt.rgba(0.06, 0.09, 0.16, 0.85)
      border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.35)
      border.width: 1

      Row {
        anchors.centerIn: parent
        spacing: Style.space(16)

        // Stick Circularity Error
        Row {
          spacing: Style.space(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Stick Err:"
            color: Qt.darker(root.foregroundColor, 1.4)
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.avgStickError.toFixed(1) + "%"
            color: root.avgStickError < 8.0 ? "#22c55e" : (root.avgStickError < 12.0 ? "#eab308" : "#ef4444")
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Snapbacks
        Row {
          spacing: Style.space(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Snapback:"
            color: Qt.darker(root.foregroundColor, 1.4)
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.snapbackCount
            color: root.snapbackCount === 0 ? "#22c55e" : "#ef4444"
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Coins collected
        Row {
          spacing: Style.space(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "🪙 Coins:"
            color: Qt.darker(root.foregroundColor, 1.4)
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.coinCount
            color: "#f59e0b"
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Jumps / Actuations
        Row {
          spacing: Style.space(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Jumps:"
            color: Qt.darker(root.foregroundColor, 1.4)
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.jumpCount
            color: root.playerColor
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ------------------------------------------------------------ Controls Banner & Reset Button
    Row {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(8)
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(12)

      // Button prompt guide
      Rectangle {
        height: Style.space(26)
        width: Style.space(360)
        radius: 4
        color: Qt.rgba(0.06, 0.09, 0.16, 0.75)
        border.color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.15)

        Text {
          anchors.centerIn: parent
          text: root.layout === "switch"
            ? "Stick / D-Pad: Move · B: Jump (hold high) · Y/A/RT: Dash"
            : (root.layout === "ps"
                ? "Stick / D-Pad: Move · ✕: Jump (hold high) · ▢/R2: Dash"
                : "Stick / D-Pad: Move · A: Jump (hold high) · X/B/RT: Dash")
          color: root.foregroundColor
          font.pixelSize: Style.font.caption
        }
      }

      // Reset Button
      Rectangle {
        height: Style.space(26)
        width: Style.space(100)
        radius: 4
        color: resetMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25) : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.08)
        border.color: root.playerColor
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "↺ Reset Run"
          color: root.playerColor
          font.bold: true
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: resetMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.resetGame()
        }
      }
    }
  }
}
