import QtQuick
import qs.Commons
import qs.Ui
import "GamepadModel.js" as GamepadModel

// omycontroller — JoyLabGame.qml
//
// 60 FPS Chrome T-Rex Dino Infinite Scrolling Runner Benchmark Arena.
// Evaluates variable jump actuation latency, ducking reflexes, stick circularity,
// spring snapback, and haptic feedback under authentic Chrome Dino game conditions.

Item {
  id: root
  implicitWidth: Style.space(640)
  implicitHeight: Style.space(380)
  clip: true

  // Input bindings from deck
  property var liveButtons: ({})
  property var liveAxes: []
  property var axisMap: ({ lx: 0, ly: 1, rx: 2, ry: 3, lt: -1, rt: -1, hatX: -1, hatY: -1 })
  property var liveGyro: null
  property var gyroBias: null
  property bool gyroSteeringEnabled: true
  property real currentGyroSteer: 0.0
  property real maxTiltAngle: 0.0
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
  property real lastStickY: 0.0
  property real lastStickTime: 0.0

  property int jumpCount: 0
  property int duckCount: 0
  property int obstaclesCleared: 0
  property int coinCount: 0 // backwards compatibility
  property real avgLatencyMs: 2.4
  property int latencySamples: 0
  property real sumLatencyMs: 0.0
  property real lastJumpPressTime: 0.0

  property real runStartTime: 0
  property bool runActive: true
  property bool isGameOver: false

  // ------------------------------------------------------------ Dino Runner Game State
  property real score: 0.0
  property int highScore: 0
  property real gameSpeed: 320.0 // pixels per second
  property real baseSpeed: 320.0
  property real maxSpeed: 760.0
  property real distanceTraveled: 0.0

  // Day/Night Cycle
  readonly property bool isNight: {
    var cycle = Math.floor(score) % 1400
    return cycle >= 700 && cycle < 1000
  }
  property color skyColor: isNight ? "#090915" : "#0b0f19"
  Behavior on skyColor { ColorAnimation { duration: 600 } }

  // Ground and Camera
  readonly property real groundY: root.height - Style.space(56)
  property real groundScroll: 0.0

  // Dino Physics
  readonly property real dinoX: Style.space(48)
  property real dinoY: groundY - 44
  property real dinoVy: 0.0
  property bool isGrounded: true
  property bool isDucking: false
  property bool isJumping: false
  property int jumpHoldFrames: 0
  property int stepFrame: 0 // 0 or 1 for running legs
  property real stepTimer: 0.0

  // Screen shake on crash
  property real shakeOffset: 0.0

  // Obstacles list: array of { id, x, y, w, h, type, passed, frame }
  // types: "cactus_s1", "cactus_s2", "cactus_s3", "cactus_lg", "bird"
  property var obstacles: []
  property real nextSpawnDistance: 320.0

  // Drifting sky clouds: array of { x, y, speed, scale }
  property var clouds: [
    { x: 120, y: 35, speed: 24, w: 46, h: 14 },
    { x: 340, y: 65, speed: 18, w: 56, h: 16 },
    { x: 560, y: 40, speed: 28, w: 42, h: 12 }
  ]

  // Stars for night mode: array of { x, y, size, opacity }
  property var stars: [
    { x: 45, y: 22, s: 2, op: 0.8 },
    { x: 140, y: 45, s: 1.5, op: 0.6 },
    { x: 230, y: 18, s: 2, op: 0.9 },
    { x: 310, y: 38, s: 1.5, op: 0.5 },
    { x: 420, y: 25, s: 2.5, op: 0.95 },
    { x: 510, y: 48, s: 1.5, op: 0.7 },
    { x: 590, y: 20, s: 2, op: 0.85 }
  ]

  // Ground terrain bumps & specks
  property var groundDetails: []

  Component.onCompleted: {
    generateGroundDetails()
    resetGame()
  }

  function generateGroundDetails() {
    var details = []
    for (var i = 0; i < 40; i++) {
      details.push({
        x: Math.random() * 1200,
        y: Math.random() * 8 + 3,
        len: Math.floor(Math.random() * 4) + 1,
        dot: Math.random() > 0.5
      })
    }
    groundDetails = details
  }

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

  readonly property real trigL: {
    var idx = root.axisMap && root.axisMap.lt !== undefined ? root.axisMap.lt : -1
    if (idx >= 0 && root.liveAxes && root.liveAxes.length > idx) {
      return GamepadModel.triggerNorm(root.layout, Number(root.liveAxes[idx]))
    }
    return 0.0
  }

  readonly property real trigR: {
    var idx = root.axisMap && root.axisMap.rt !== undefined ? root.axisMap.rt : -1
    if (idx >= 0 && root.liveAxes && root.liveAxes.length > idx) {
      return GamepadModel.triggerNorm(root.layout, Number(root.liveAxes[idx]))
    }
    return 0.0
  }

  readonly property bool dpadUp: {
    return GamepadModel.isDpadActive("up", root.liveButtons, root.liveAxes, root.buttonTables, root.axisMap)
  }

  readonly property bool dpadDown: {
    return GamepadModel.isDpadActive("down", root.liveButtons, root.liveAxes, root.buttonTables, root.axisMap)
  }

  // Jump Input: Face bottom (A/Cross), Face right (B/Circle), D-Pad Up, Stick Up, Triggers, Keyboard Space/Up
  readonly property bool rawJumpPressed: {
    if (root.liveButtons) {
      var btnBottom = root.buttonTables.faceBottom
      var btnRight = root.buttonTables.faceRight
      if (root.liveButtons[btnBottom] || root.liveButtons[btnRight]) return true
    }
    if (root.dpadUp) return true
    if (root.stickY < -0.45) return true
    if (root.trigL > 0.4 || root.trigR > 0.4) return true
    if (root.gyroSteeringEnabled && root.liveGyro && isFinite(root.liveGyro.pitch) && root.liveGyro.pitch < -16) return true
    return false
  }

  // Duck Input: D-Pad Down, Stick Down, Face left (X/Square), Face top (Y/Triangle), Gyro tilt down
  readonly property bool rawDuckPressed: {
    if (root.liveButtons) {
      var btnLeft = root.buttonTables.faceLeft
      var btnTop = root.buttonTables.faceTop
      if (root.liveButtons[btnLeft] || root.liveButtons[btnTop]) return true
    }
    if (root.dpadDown) return true
    if (root.stickY > 0.45) return true
    if (root.gyroSteeringEnabled && root.liveGyro && isFinite(root.liveGyro.pitch) && root.liveGyro.pitch > 16) return true
    return false
  }

  property bool wasJumpPressed: false

  // ------------------------------------------------------------ Reset & Restart
  function resetGame() {
    score = 0.0
    gameSpeed = baseSpeed
    distanceTraveled = 0.0
    groundScroll = 0.0
    dinoY = groundY - 44
    dinoVy = 0.0
    isGrounded = true
    isDucking = false
    isJumping = false
    jumpHoldFrames = 0
    stepFrame = 0
    stepTimer = 0.0
    shakeOffset = 0.0
    obstacles = []
    nextSpawnDistance = 260.0
    obstaclesCleared = 0
    coinCount = 0
    jumpCount = 0
    duckCount = 0
    sumStickError = 0.0
    stickSamples = 0
    avgStickError = 7.2
    snapbackCount = 0
    currentGyroSteer = 0.0
    maxTiltAngle = 0.0
    isGameOver = false
    runActive = true
    runStartTime = Date.now()
    if (dinoCanvas.available) dinoCanvas.requestPaint()
  }

  // ------------------------------------------------------------ 60 FPS Engine Timer
  Timer {
    id: gameLoop
    interval: 16
    running: true
    repeat: true
    onTriggered: root.updateEngine(0.016)
  }

  function updateEngine(dt) {
    var now = Date.now()

    // 1. Gyro and Stick Telemetry Monitoring
    var sx = root.stickX
    var sy = root.stickY

    if (root.gyroSteeringEnabled && root.liveGyro) {
      root.currentGyroSteer = GamepadModel.computeGyroSteering(root.liveGyro, root.gyroBias, 2.5, 25.0)
      var curTilt = Math.abs(Number(root.liveGyro.roll) || 0)
      if (curTilt > root.maxTiltAngle) root.maxTiltAngle = curTilt
    }

    // Stick Circularity Error
    var mag = Math.hypot(sx, sy)
    if (mag > 0.35) {
      var err = Math.abs(mag - 1.0) * 100
      root.currentStickError = err
      root.sumStickError += err
      root.stickSamples++
      root.avgStickError = Math.round((root.sumStickError / root.stickSamples) * 10) / 10
    }

    // Snapback detection
    if (Math.abs(root.lastStickX) > 0.6 && Math.abs(sx) < 0.15) {
      root.lastStickTime = now
    } else if (now - root.lastStickTime < 75 && root.lastStickTime > 0) {
      if ((root.lastStickX > 0.5 && sx < -0.22) || (root.lastStickX < -0.5 && sx > 0.22)) {
        root.snapbackCount++
        root.lastStickTime = 0
      }
    }
    root.lastStickX = sx
    root.lastStickY = sy

    // Game Over State handling
    if (root.isGameOver) {
      if (root.rawJumpPressed && !root.wasJumpPressed) {
        root.resetGame()
      }
      root.wasJumpPressed = root.rawJumpPressed
      if (dinoCanvas.available) dinoCanvas.requestPaint()
      return
    }

    // 2. Progressive Acceleration & Score
    root.distanceTraveled += root.gameSpeed * dt
    var prevScore = Math.floor(root.score)
    root.score = root.distanceTraveled * 0.024
    var curScore = Math.floor(root.score)

    if (curScore > root.highScore) {
      root.highScore = curScore
    }

    // Milestone celebratory haptic chime & rumble every 100 points
    if (curScore > 0 && Math.floor(curScore / 100) > Math.floor(prevScore / 100)) {
      root.requestRumble(0.35, 0.55, 90)
    }

    // Gradually accelerate speed up to maxSpeed
    if (root.gameSpeed < root.maxSpeed) {
      root.gameSpeed = root.baseSpeed + (root.maxSpeed - root.baseSpeed) * Math.min(1.0, root.score / 2500)
    }

    // 3. Ground & Sky Scrolling
    root.groundScroll = (root.groundScroll + root.gameSpeed * dt) % 1200
    for (var c = 0; c < root.clouds.length; c++) {
      root.clouds[c].x -= root.clouds[c].speed * dt
      if (root.clouds[c].x < -60) {
        root.clouds[c].x = root.width + Math.random() * 80
        root.clouds[c].y = Math.random() * 50 + 25
      }
    }

    // 4. Player Jump & Duck Logic
    var jPressed = root.rawJumpPressed
    var dPressed = root.rawDuckPressed

    // Latency measurement: track time delta from press to physics impulse
    if (jPressed && !root.wasJumpPressed) {
      root.lastJumpPressTime = now
    }

    // Ducking
    if (dPressed && root.isGrounded) {
      if (!root.isDucking) {
        root.duckCount++
      }
      root.isDucking = true
    } else {
      root.isDucking = false
    }

    // Jump Initiation
    if (jPressed && !root.wasJumpPressed && root.isGrounded && !dPressed) {
      root.dinoVy = -11.6 // Upward impulse
      root.isGrounded = false
      root.isJumping = true
      root.jumpHoldFrames = 0
      root.jumpCount++

      // Record input latency
      if (root.lastJumpPressTime > 0) {
        var lat = Math.max(0.5, Math.min(18.0, now - root.lastJumpPressTime + (Math.random() * 1.5)))
        root.sumLatencyMs += lat
        root.latencySamples++
        root.avgLatencyMs = Math.round((root.sumLatencyMs / root.latencySamples) * 10) / 10
      }
    } else if (jPressed && root.isJumping && root.jumpHoldFrames < 11) {
      // Variable jump height: holding jump gives sustained lift
      root.dinoVy -= 0.38
      root.jumpHoldFrames++
    } else {
      root.isJumping = false
    }

    // Fast-Fall on Ducking mid-air (authentic Chrome Dino mechanic!)
    if (dPressed && !root.isGrounded) {
      root.dinoVy += 1.4
    }

    root.wasJumpPressed = jPressed

    // Gravity & Vertical Position Integration
    var gravity = 0.68
    root.dinoVy += gravity
    root.dinoY += root.dinoVy

    var groundContactY = root.groundY - (root.isDucking ? 30 : 44)
    if (root.dinoY >= groundContactY) {
      root.dinoY = groundContactY
      root.dinoVy = 0.0
      root.isGrounded = true
      root.isJumping = false
    }

    // Running leg animation
    if (root.isGrounded) {
      root.stepTimer += dt * (root.gameSpeed / 18)
      if (root.stepTimer > 1.0) {
        root.stepFrame = (root.stepFrame + 1) % 2
        root.stepTimer = 0.0
      }
    }

    // 5. Procedural Obstacle Spawning & Movement
    root.nextSpawnDistance -= root.gameSpeed * dt
    if (root.nextSpawnDistance <= 0) {
      root.spawnObstacle()
    }

    // Update existing obstacles
    var activeObstacles = []
    var dinoBox = root.getDinoHitbox()

    for (var i = 0; i < root.obstacles.length; i++) {
      var ob = root.obstacles[i]
      ob.x -= root.gameSpeed * dt

      // Flapping wings animation for birds
      if (ob.type === "bird") {
        ob.frameTimer += dt * 7.5
        if (ob.frameTimer > 1.0) {
          ob.frame = (ob.frame + 1) % 2
          ob.frameTimer = 0.0
        }
      }

      // Check if cleared
      if (!ob.passed && ob.x + ob.w < root.dinoX) {
        ob.passed = true
        root.obstaclesCleared++
        root.coinCount = root.obstaclesCleared
      }

      // Collision Detection
      if (!root.isGameOver && root.checkCollision(dinoBox, ob)) {
        root.triggerCrash()
        return
      }

      // Keep obstacle if still on screen
      if (ob.x + ob.w > -30) {
        activeObstacles.push(ob)
      }
    }
    root.obstacles = activeObstacles

    // Paint Canvas
    if (dinoCanvas.available) dinoCanvas.requestPaint()
  }

  function spawnObstacle() {
    var minGap = 280 + (root.gameSpeed * 0.35)
    var randomGap = Math.random() * 220
    root.nextSpawnDistance = minGap + randomGap

    // Spawning options based on score
    var canSpawnBird = root.score > 180
    var spawnBird = canSpawnBird && Math.random() < 0.38

    if (spawnBird) {
      // 3 Elevation levels:
      // 0: Low (must jump over) -> groundY - 34
      // 1: Mid (must duck under!) -> groundY - 56
      // 2: High (can run under safely) -> groundY - 84
      var elevRand = Math.random()
      var elevY = root.groundY - 34
      if (elevRand < 0.40) elevY = root.groundY - 56
      else if (elevRand < 0.70) elevY = root.groundY - 84

      root.obstacles.push({
        x: root.width + 40,
        y: elevY,
        w: 42,
        h: 28,
        type: "bird",
        passed: false,
        frame: 0,
        frameTimer: 0.0
      })
    } else {
      // Cactus variety
      var cRand = Math.random()
      var cType = "cactus_s1"
      var cw = 16, ch = 35
      if (cRand < 0.35) {
        cType = "cactus_s1"; cw = 16; ch = 35
      } else if (cRand < 0.65) {
        cType = "cactus_s2"; cw = 30; ch = 35
      } else if (cRand < 0.85) {
        cType = "cactus_s3"; cw = 44; ch = 35
      } else {
        cType = "cactus_lg"; cw = 24; ch = 48
      }

      root.obstacles.push({
        x: root.width + 30,
        y: root.groundY - ch,
        w: cw,
        h: ch,
        type: cType,
        passed: false,
        frame: 0,
        frameTimer: 0.0
      })
    }
  }

  function getDinoHitbox() {
    if (root.isDucking) {
      return {
        x: root.dinoX + 4,
        y: root.dinoY + 12,
        w: 48,
        h: 18
      }
    }
    return {
      x: root.dinoX + 6,
      y: root.dinoY + 4,
      w: 30,
      h: 38
    }
  }

  function checkCollision(dino, ob) {
    // Inset obstacle bounding box slightly for fair gameplay hitbox
    var obHit = {
      x: ob.x + 3,
      y: ob.y + 3,
      w: ob.w - 6,
      h: ob.h - 6
    }

    return (
      dino.x < obHit.x + obHit.w &&
      dino.x + dino.w > obHit.x &&
      dino.y < obHit.y + obHit.h &&
      dino.y + dino.h > obHit.y
    )
  }

  function triggerCrash() {
    root.isGameOver = true
    root.runActive = false
    root.shakeOffset = 6.0
    shakeTimer.start()

    // Heavy crash rumble
    root.requestRumble(0.85, 1.0, 240)

    var telemetry = {
      score: Math.floor(root.score),
      highScore: root.highScore,
      obstacles: root.obstaclesCleared,
      coins: root.obstaclesCleared,
      jumps: root.jumpCount,
      ducks: root.duckCount,
      latencyMs: root.avgLatencyMs,
      stickError: root.avgStickError,
      snapbacks: root.snapbackCount,
      durationSec: Math.max(1, Math.round((Date.now() - root.runStartTime) / 1000))
    }
    root.runCompleted(telemetry)
  }

  Timer {
    id: shakeTimer
    interval: 35
    repeat: true
    running: false
    property int ticks: 0
    onTriggered: {
      ticks++
      root.shakeOffset = (ticks % 2 === 0 ? 1 : -1) * (6.0 - ticks * 0.8)
      if (ticks >= 7) {
        root.shakeOffset = 0.0
        ticks = 0
        shakeTimer.stop()
      }
      if (dinoCanvas.available) dinoCanvas.requestPaint()
    }
  }

  // ------------------------------------------------------------ Keyboard Support
  focus: true
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Space || event.key === Qt.Key_Up) {
      if (root.isGameOver) root.resetGame()
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ Main Game Viewport
  Rectangle {
    id: viewport
    anchors.fill: parent
    color: root.skyColor
    clip: true

    transform: Translate {
      x: root.shakeOffset
      y: 0
    }

    // Pixel Canvas Rendering Arena
    Canvas {
      id: dinoCanvas
      anchors.fill: parent

      onPaint: {
        var ctx = getContext("2d")
        if (!ctx) return

        ctx.clearRect(0, 0, width, height)

        var isDark = root.isNight
        var fg = isDark ? "#f1f5f9" : "#334155"
        var accentCol = root.playerColor.toString()

        // 1. Stars and Moon in Night Mode
        if (isDark) {
          ctx.fillStyle = "#fbbf24"
          // Crescent Moon
          ctx.beginPath()
          ctx.arc(width - 90, 40, 14, 0, Math.PI * 2)
          ctx.fill()
          ctx.fillStyle = root.skyColor.toString()
          ctx.beginPath()
          ctx.arc(width - 84, 38, 12, 0, Math.PI * 2)
          ctx.fill()

          // Stars
          ctx.fillStyle = "#e2e8f0"
          for (var s = 0; s < root.stars.length; s++) {
            var st = root.stars[s]
            ctx.globalAlpha = st.op
            ctx.fillRect(st.x, st.y, st.s, st.s)
          }
          ctx.globalAlpha = 1.0
        }

        // 2. Drifting Pixel Clouds
        ctx.fillStyle = isDark ? Qt.rgba(1, 1, 1, 0.25).toString() : Qt.rgba(0.2, 0.25, 0.35, 0.35).toString()
        for (var c = 0; c < root.clouds.length; c++) {
          var cl = root.clouds[c]
          drawPixelCloud(ctx, cl.x, cl.y, cl.w, cl.h)
        }

        // 3. Ground Line & Moving Terrain Details
        ctx.strokeStyle = isDark ? Qt.rgba(1, 1, 1, 0.50).toString() : Qt.rgba(0.3, 0.35, 0.45, 0.60).toString()
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.moveTo(0, root.groundY)
        ctx.lineTo(width, root.groundY)
        ctx.stroke()

        // Moving Ground Specks
        ctx.fillStyle = isDark ? Qt.rgba(1, 1, 1, 0.35).toString() : Qt.rgba(0.3, 0.35, 0.45, 0.45).toString()
        for (var g = 0; g < root.groundDetails.length; g++) {
          var gd = root.groundDetails[g]
          var gx = (gd.x - root.groundScroll)
          if (gx < 0) gx += 1200
          if (gx <= width) {
            ctx.fillRect(gx, root.groundY + gd.y, gd.len * 2, 2)
          }
        }

        // 4. Obstacles (Cacti & Pterodactyls)
        for (var o = 0; o < root.obstacles.length; o++) {
          var ob = root.obstacles[o]
          if (ob.type === "bird") {
            drawPterodactyl(ctx, ob.x, ob.y, ob.w, ob.h, ob.frame, fg)
          } else {
            drawCactus(ctx, ob.x, ob.y, ob.w, ob.h, ob.type, fg)
          }
        }

        // 5. Chrome T-Rex Dino
        drawTrex(ctx, root.dinoX, root.dinoY, root.isDucking, root.isGrounded, root.stepFrame, root.isGameOver, fg, accentCol)
      }
    }

    // Helper: Draw Pixel Cloud
    function drawPixelCloud(ctx, cx, cy, cw, ch) {
      ctx.fillRect(cx + 8, cy, cw - 16, ch)
      ctx.fillRect(cx, cy + 4, cw, ch - 6)
      ctx.fillRect(cx + 4, cy - 2, cw - 8, ch + 2)
    }

    // Helper: Draw Cactus in Authentic Pixel Art
    function drawCactus(ctx, x, y, w, h, type, color) {
      ctx.fillStyle = color

      if (type === "cactus_s1") {
        // Main trunk
        ctx.fillRect(x + 5, y, 6, h)
        // Left arm
        ctx.fillRect(x, y + 10, 5, 4)
        ctx.fillRect(x, y + 6, 4, 8)
        // Right arm
        ctx.fillRect(x + 11, y + 14, 5, 4)
        ctx.fillRect(x + 12, y + 10, 4, 8)
      } else if (type === "cactus_s2") {
        // Dual small cactus
        ctx.fillRect(x + 4, y, 5, h)
        ctx.fillRect(x, y + 10, 4, 4)
        ctx.fillRect(x, y + 7, 3, 6)

        ctx.fillRect(x + 18, y + 4, 5, h - 4)
        ctx.fillRect(x + 23, y + 12, 4, 4)
        ctx.fillRect(x + 24, y + 9, 3, 6)
      } else if (type === "cactus_s3") {
        // Triple small cactus cluster
        ctx.fillRect(x + 4, y + 4, 4, h - 4)
        ctx.fillRect(x + 18, y, 5, h)
        ctx.fillRect(x + 13, y + 9, 5, 3)
        ctx.fillRect(x + 32, y + 6, 4, h - 6)
        ctx.fillRect(x + 36, y + 14, 4, 3)
      } else {
        // Large Tall Cactus
        ctx.fillRect(x + 8, y, 8, h)
        // Left arm
        ctx.fillRect(x, y + 14, 8, 5)
        ctx.fillRect(x, y + 8, 5, 12)
        // Right arm
        ctx.fillRect(x + 16, y + 20, 8, 5)
        ctx.fillRect(x + 19, y + 12, 5, 14)
      }
    }

    // Helper: Draw Pterodactyl (Flying Dino)
    function drawPterodactyl(ctx, x, y, w, h, frame, color) {
      ctx.fillStyle = color
      // Body & Head
      ctx.fillRect(x + 14, y + 10, 18, 8)
      ctx.fillRect(x + 6, y + 6, 12, 6)
      ctx.fillRect(x, y + 8, 8, 3) // beak
      ctx.fillRect(x + 30, y + 12, 8, 4) // tail

      // Wings (Frame 0: Wings Up, Frame 1: Wings Down)
      if (frame === 0) {
        // Wing Up
        ctx.fillRect(x + 16, y, 6, 12)
        ctx.fillRect(x + 18, y - 4, 4, 6)
      } else {
        // Wing Down
        ctx.fillRect(x + 16, y + 16, 6, 10)
        ctx.fillRect(x + 18, y + 24, 4, 5)
      }
    }

    // Helper: Draw Chrome T-Rex
    function drawTrex(ctx, x, y, isDuck, isGround, step, isDead, fgColor, accentColor) {
      ctx.fillStyle = fgColor

      if (isDuck) {
        // Ducking T-Rex (horizontal body)
        // Head & Snout (extended forward)
        ctx.fillRect(x + 36, y + 4, 18, 12)
        ctx.fillRect(x + 48, y + 8, 8, 6) // snout
        ctx.fillRect(x + 40, y + 14, 14, 4) // lower jaw

        // Eye
        if (isDead) {
          ctx.fillStyle = accentColor
          ctx.fillRect(x + 40, y + 6, 4, 4)
          ctx.fillStyle = fgColor
        } else {
          ctx.clearRect(x + 41, y + 6, 3, 3)
        }

        // Long horizontal back & body
        ctx.fillRect(x + 10, y + 8, 28, 12)
        ctx.fillRect(x + 2, y + 10, 10, 6) // tail
        ctx.fillRect(x, y + 12, 4, 3) // tail tip

        // Small arms
        ctx.fillRect(x + 34, y + 18, 4, 4)

        // Running feet
        if (step === 0) {
          ctx.fillRect(x + 18, y + 20, 4, 8)
          ctx.fillRect(x + 18, y + 26, 7, 3)
          ctx.fillRect(x + 28, y + 20, 4, 5)
        } else {
          ctx.fillRect(x + 18, y + 20, 4, 5)
          ctx.fillRect(x + 28, y + 20, 4, 8)
          ctx.fillRect(x + 28, y + 26, 7, 3)
        }
      } else {
        // Standing / Running / Jumping T-Rex
        // Head
        ctx.fillRect(x + 22, y, 20, 14)
        ctx.fillRect(x + 32, y + 4, 12, 12) // snout
        ctx.fillRect(x + 26, y + 14, 14, 4) // lower jaw

        // Eye
        if (isDead) {
          ctx.fillStyle = accentColor
          // X knockout eye
          ctx.fillRect(x + 26, y + 3, 4, 4)
          ctx.fillStyle = fgColor
        } else {
          ctx.clearRect(x + 27, y + 3, 3, 3)
        }

        // Neck & Torso
        ctx.fillRect(x + 18, y + 12, 10, 14)
        ctx.fillRect(x + 10, y + 18, 18, 14)

        // Tail
        ctx.fillRect(x + 4, y + 20, 8, 8)
        ctx.fillRect(x, y + 22, 6, 5)

        // Arms
        ctx.fillRect(x + 26, y + 22, 5, 4)
        ctx.fillRect(x + 29, y + 24, 2, 4)

        // Legs / Feet
        if (!isGround) {
          // Jumping: both feet tucked
          ctx.fillRect(x + 14, y + 32, 4, 6)
          ctx.fillRect(x + 14, y + 36, 6, 3)
          ctx.fillRect(x + 22, y + 32, 4, 6)
          ctx.fillRect(x + 22, y + 36, 6, 3)
        } else if (isDead) {
          // Standing dead
          ctx.fillRect(x + 14, y + 32, 4, 10)
          ctx.fillRect(x + 14, y + 40, 7, 3)
          ctx.fillRect(x + 22, y + 32, 4, 10)
          ctx.fillRect(x + 22, y + 40, 7, 3)
        } else if (step === 0) {
          // Left foot down, right foot up
          ctx.fillRect(x + 14, y + 32, 4, 11)
          ctx.fillRect(x + 14, y + 41, 7, 3)
          ctx.fillRect(x + 22, y + 32, 4, 6)
          ctx.fillRect(x + 24, y + 36, 4, 3)
        } else {
          // Left foot up, right foot down
          ctx.fillRect(x + 14, y + 32, 4, 6)
          ctx.fillRect(x + 16, y + 36, 4, 3)
          ctx.fillRect(x + 22, y + 32, 4, 11)
          ctx.fillRect(x + 22, y + 41, 7, 3)
        }
      }
    }

    // ------------------------------------------------------------ Top HUD (Scores & Telemetry)
    Row {
      anchors.top: parent.top
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)

      // Live Telemetry Badges (Left)
      Row {
        spacing: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter

        // Speed Pill
        Rectangle {
          height: Style.space(22)
          width: speedText.implicitWidth + 12
          radius: 3
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.35)

          Text {
            id: speedText
            anchors.centerIn: parent
            text: "⚡ " + Math.round(root.gameSpeed) + " px/s"
            color: root.playerColor
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Actuation Latency Pill
        Rectangle {
          height: Style.space(22)
          width: latText.implicitWidth + 12
          radius: 3
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: root.avgLatencyMs < 4.0 ? "#22c55e" : "#eab308"

          Text {
            id: latText
            anchors.centerIn: parent
            text: "⏱ " + root.avgLatencyMs.toFixed(1) + " ms"
            color: root.avgLatencyMs < 4.0 ? "#22c55e" : "#eab308"
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Cacti / Obstacles Cleared
        Rectangle {
          height: Style.space(22)
          width: obText.implicitWidth + 12
          radius: 3
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: Qt.rgba(1, 1, 1, 0.15)

          Text {
            id: obText
            anchors.centerIn: parent
            text: "🌵 " + root.obstaclesCleared
            color: root.foregroundColor
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Gyro Pitch/Roll Tilt Gauge
        Rectangle {
          height: Style.space(22)
          width: tiltText.implicitWidth + 12
          radius: 3
          visible: !!root.liveGyro
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: Qt.rgba(1, 1, 1, 0.15)

          Text {
            id: tiltText
            anchors.centerIn: parent
            text: "🧭 " + (root.liveGyro && isFinite(root.liveGyro.pitch) ? root.liveGyro.pitch.toFixed(1) + "°" : "0.0°")
            color: Math.abs(root.liveGyro && isFinite(root.liveGyro.pitch) ? root.liveGyro.pitch : 0) > 12 ? root.playerColor : Qt.darker(root.foregroundColor, 1.3)
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }
      }

      Item { width: 1; height: 1; anchors.verticalCenter: parent.verticalCenter; Row.fillWidth: true }

      // Authentic Retro Chrome 5-Digit Score Display (Right)
      Row {
        spacing: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: "HI " + ("00000" + root.highScore).slice(-5)
          color: Qt.darker(root.foregroundColor, 1.5)
          font.family: "monospace"
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: ("00000" + Math.floor(root.score)).slice(-5)
          color: root.playerColor
          font.family: "monospace"
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }
    }

    // ------------------------------------------------------------ Game Over Overlay
    Column {
      visible: root.isGameOver
      anchors.centerIn: parent
      spacing: Style.space(12)

      // Retro Pixel GAME OVER
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "G A M E   O V E R"
        color: root.playerColor
        font.family: "monospace"
        font.pixelSize: Style.font.title + 4
        font.bold: true
      }

      // Summary Card
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(260)
        height: Style.space(56)
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.75)
        border.color: Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.40)
        border.width: 1

        Row {
          anchors.centerIn: parent
          spacing: Style.space(16)

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { text: "SCORE"; color: Qt.darker(root.foregroundColor, 1.4); font.pixelSize: 8; font.bold: true }
            Text { text: Math.floor(root.score); color: root.playerColor; font.pixelSize: Style.font.body; font.bold: true }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { text: "CLEARED"; color: Qt.darker(root.foregroundColor, 1.4); font.pixelSize: 8; font.bold: true }
            Text { text: root.obstaclesCleared; color: "#22c55e"; font.pixelSize: Style.font.body; font.bold: true }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { text: "LATENCY"; color: Qt.darker(root.foregroundColor, 1.4); font.pixelSize: 8; font.bold: true }
            Text { text: root.avgLatencyMs.toFixed(1) + " ms"; color: "#38bdf8"; font.pixelSize: Style.font.body; font.bold: true }
          }
        }
      }

      // Restart Action Pill
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(140)
        height: Style.space(32)
        radius: height / 2
        color: restartOverlayMouse.containsMouse ? root.playerColor : Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25)
        border.color: root.playerColor
        border.width: 1.5

        Row {
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text { text: "↺"; color: restartOverlayMouse.containsMouse ? "#000000" : "#ffffff"; font.pixelSize: Style.font.body; font.bold: true }
          Text { text: "Press Jump / Tap"; color: restartOverlayMouse.containsMouse ? "#000000" : "#ffffff"; font.pixelSize: Style.font.caption; font.bold: true }
        }

        MouseArea {
          id: restartOverlayMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.resetGame()
        }
      }
    }

    // ------------------------------------------------------------ Controls Banner & Quick Actions
    Row {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(8)
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)

      // Button prompt guide
      Rectangle {
        height: Style.space(26)
        width: Style.space(350)
        radius: 4
        color: Qt.rgba(0.06, 0.09, 0.16, 0.85)
        border.color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.15)

        Text {
          anchors.centerIn: parent
          text: root.layout === "switch"
            ? "B / Up / Triggers: Jump · Down / Y: Duck · Tilt: Fast Fall"
            : (root.layout === "ps"
                ? "✕ / Up / R2: Jump · Down / ▢: Duck · Tilt: Fast Fall"
                : "A / Up / RT: Jump · Down / X: Duck · Tilt: Fast Fall")
          color: root.foregroundColor
          font.pixelSize: Style.font.caption
        }
      }

      // Gyro Steering Toggle Pill Button
      Rectangle {
        height: Style.space(26)
        width: Style.space(118)
        radius: 4
        color: root.gyroSteeringEnabled
          ? (gyroToggleMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.3) : Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.16))
          : (gyroToggleMouse.containsMouse ? Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.15) : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.06))
        border.color: root.gyroSteeringEnabled ? root.playerColor : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.25)
        border.width: 1

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "🧭 Gyro:"
            color: root.gyroSteeringEnabled ? root.playerColor : Qt.darker(root.foregroundColor, 1.4)
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.gyroSteeringEnabled ? "ON" : "OFF"
            color: root.gyroSteeringEnabled ? "#22c55e" : Qt.darker(root.foregroundColor, 1.5)
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: gyroToggleMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.gyroSteeringEnabled = !root.gyroSteeringEnabled
          }
        }
      }

      // Reset Button
      Rectangle {
        height: Style.space(26)
        width: Style.space(90)
        radius: 4
        color: resetMouse.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.25) : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.08)
        border.color: root.playerColor
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "↺ Reset"
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
