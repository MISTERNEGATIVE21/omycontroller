import QtQuick
import qs.Commons
import "GamepadModel.js" as GamepadModel

// Quatro — CircularityRadar.qml
//
// Gamepadla-style stick circularity radar and drift diagnostics canvas.
// Visualizes Cartesian crosshairs, 50% guide circle, 100% boundary circle (r = 1.0),
// deadzone shaded circle, coordinate tracer trail with fading alpha, and live coordinate
// marker dot.
//
// Displays live diagnostics:
//   - Live X, Y coordinate values
//   - Radial magnitude R = sqrt(x^2 + y^2)
//   - Circularity Error % (deviation from ideal unit circle r = 1.0)
//   - Center Drift % (resting center deviation)
//
// Pure QML, zero external C++ plugins, theme-aware via qs.Commons (Color, Style).

Rectangle {
  id: root

  property string title: "Stick Circularity"
  property real rawX: 0.0
  property real rawY: 0.0
  property real deadzone: 0.10
  property color playerColor: Color.accent
  property bool showLabels: true
  property bool showMetrics: true
  property bool cardBackground: true
  property real radarSize: 180

  implicitWidth: Style.space(220)
  implicitHeight: Style.space(260)

  radius: Style.radius(8)
  color: cardBackground ? Color.popups.background : "transparent"
  border.color: cardBackground ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.18) : "transparent"
  border.width: cardBackground ? 1 : 0

  // ------------------------------------------------------------- state
  property var history: []
  property real circularityError: 0.0
  property real centerDriftPercent: 0.0
  property real currentR: Math.sqrt(rawX * rawX + rawY * rawY)

  readonly property color glyphColor: Color.popups.text
  readonly property color dimGlyph: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.55)
  readonly property color faintBorder: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.15)
  readonly property color chipBackground: Qt.rgba(glyphColor.r, glyphColor.g, glyphColor.b, 0.07)

  onRawXChanged: pushCoord()
  onRawYChanged: pushCoord()

  function pushCoord() {
    var nx = Number(rawX) || 0
    var ny = Number(rawY) || 0
    var r = Math.sqrt(nx * nx + ny * ny)
    currentR = r

    // Update center drift when stick is resting near center
    if (r <= 0.20) {
      centerDriftPercent = Math.round(r * 1000) / 10
    }

    var m = GamepadModel.circularityMetrics(nx, ny, history)
    history = m.history
    circularityError = m.circularityError
    radarCanvas.requestPaint()
  }

  function reset() {
    history = []
    circularityError = 0
    var nx = Number(rawX) || 0
    var ny = Number(rawY) || 0
    var r = Math.sqrt(nx * nx + ny * ny)
    currentR = r
    centerDriftPercent = Math.round(r * 1000) / 10
    radarCanvas.requestPaint()
  }

  // ----------------------------------------------------------- UI layout
  Column {
    id: mainCol
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    // Header: Title + Reset Button
    Row {
      width: parent.width
      visible: root.showLabels

      Text {
        width: parent.width - resetBtn.width
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        color: root.glyphColor
        elide: Text.ElideRight
      }

      Rectangle {
        id: resetBtn
        width: Style.space(52)
        height: Style.space(18)
        radius: Style.radius(4)
        color: resetArea.containsMouse ? Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.2) : root.chipBackground
        border.color: resetArea.containsMouse ? root.playerColor : root.faintBorder
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "↺ Reset"
          font.family: Style.font.family
          font.pixelSize: 8
          font.bold: true
          color: resetArea.containsMouse ? root.playerColor : root.dimGlyph
        }

        MouseArea {
          id: resetArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.reset()
        }
      }
    }

    // Radar Canvas
    Item {
      id: radarContainer
      width: parent.width
      height: Math.max(80, parent.height - (root.showMetrics ? Style.space(78) : 0) - (root.showLabels ? Style.space(24) : 0))

      Canvas {
        id: radarCanvas
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        antialiasing: true

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)

          var cx = width / 2
          var cy = height / 2
          var Rmax = (width / 2) * 0.94
          var R1 = Rmax * 0.82
          var R05 = R1 * 0.5
          var Rdz = R1 * Math.max(0.02, root.deadzone)

          // 1. Base radar disc
          ctx.beginPath()
          ctx.arc(cx, cy, Rmax, 0, 2 * Math.PI)
          ctx.fillStyle = Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.04)
          ctx.fill()
          ctx.lineWidth = 1
          ctx.strokeStyle = Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.12)
          ctx.stroke()

          // 2. Cartesian crosshairs
          ctx.beginPath()
          ctx.moveTo(cx - Rmax, cy)
          ctx.lineTo(cx + Rmax, cy)
          ctx.moveTo(cx, cy - Rmax)
          ctx.lineTo(cx, cy + Rmax)
          ctx.lineWidth = 1
          ctx.strokeStyle = Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.18)
          ctx.stroke()

          // Ticks at 0.25, 0.5, 0.75, 1.0
          var ticks = [0.25, 0.5, 0.75, 1.0]
          ctx.beginPath()
          for (var t = 0; t < ticks.length; t++) {
            var tr = R1 * ticks[t]
            ctx.moveTo(cx + tr, cy - 3); ctx.lineTo(cx + tr, cy + 3)
            ctx.moveTo(cx - tr, cy - 3); ctx.lineTo(cx - tr, cy + 3)
            ctx.moveTo(cx - 3, cy + tr); ctx.lineTo(cx + 3, cy + tr)
            ctx.moveTo(cx - 3, cy - tr); ctx.lineTo(cx + 3, cy - tr)
          }
          ctx.strokeStyle = Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.28)
          ctx.stroke()

          // 3. 50% guide circle
          ctx.beginPath()
          ctx.arc(cx, cy, R05, 0, 2 * Math.PI)
          ctx.lineWidth = 1
          ctx.strokeStyle = Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.22)
          ctx.stroke()

          // 4. 100% boundary circle (r = 1.0)
          ctx.beginPath()
          ctx.arc(cx, cy, R1, 0, 2 * Math.PI)
          ctx.lineWidth = 1.5
          ctx.strokeStyle = Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.45)
          ctx.stroke()

          // 5. Deadzone shaded circle
          ctx.beginPath()
          ctx.arc(cx, cy, Rdz, 0, 2 * Math.PI)
          ctx.fillStyle = Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.14)
          ctx.fill()
          ctx.lineWidth = 1.5
          ctx.strokeStyle = Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.45)
          ctx.stroke()

          // 6. History trace trail points with fading alpha
          var pts = root.history || []
          var ptCount = pts.length
          if (ptCount > 0) {
            for (var i = 0; i < ptCount; i++) {
              var p = pts[i]
              var alpha = 0.10 + 0.65 * (i / Math.max(1, ptCount - 1))
              var px = cx + p.x * R1
              var py = cy + p.y * R1

              ctx.beginPath()
              ctx.arc(px, py, 2.5, 0, 2 * Math.PI)
              ctx.fillStyle = Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, alpha)
              ctx.fill()
            }
          }

          // 7. Live coordinate marker dot and vector stem line
          var livePx = cx + root.rawX * R1
          var livePy = cy + root.rawY * R1

          // Vector line from origin to live stick coordinate
          ctx.beginPath()
          ctx.moveTo(cx, cy)
          ctx.lineTo(livePx, livePy)
          ctx.lineWidth = 2
          ctx.strokeStyle = Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.55)
          ctx.stroke()

          // Outer halo around active dot
          ctx.beginPath()
          ctx.arc(livePx, livePy, 7, 0, 2 * Math.PI)
          ctx.fillStyle = Qt.rgba(root.playerColor.r, root.playerColor.g, root.playerColor.b, 0.35)
          ctx.fill()
          ctx.lineWidth = 1.5
          ctx.strokeStyle = root.playerColor
          ctx.stroke()

          // Inner solid center dot
          ctx.beginPath()
          ctx.arc(livePx, livePy, 3.5, 0, 2 * Math.PI)
          ctx.fillStyle = Color.popups.background
          ctx.fill()
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.reset()
        }
      }
    }

    // ------------------------------------------------------ Readouts & Metrics
    Column {
      id: metricsCol
      width: parent.width
      visible: root.showMetrics
      spacing: Style.space(4)

      // Row 1: X, Y, R live readouts
      Row {
        width: parent.width
        spacing: Style.space(4)

        Rectangle {
          width: (parent.width - Style.space(8)) / 3
          height: Style.space(20)
          radius: Style.radius(4)
          color: root.chipBackground
          border.color: root.faintBorder
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "X " + (root.rawX >= 0 ? "+" : "") + root.rawX.toFixed(3)
            font.family: Style.font.family
            font.pixelSize: 9
            color: root.glyphColor
          }
        }

        Rectangle {
          width: (parent.width - Style.space(8)) / 3
          height: Style.space(20)
          radius: Style.radius(4)
          color: root.chipBackground
          border.color: root.faintBorder
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "Y " + (root.rawY >= 0 ? "+" : "") + root.rawY.toFixed(3)
            font.family: Style.font.family
            font.pixelSize: 9
            color: root.glyphColor
          }
        }

        Rectangle {
          width: (parent.width - Style.space(8)) / 3
          height: Style.space(20)
          radius: Style.radius(4)
          color: root.chipBackground
          border.color: root.faintBorder
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "R " + root.currentR.toFixed(3)
            font.family: Style.font.family
            font.pixelSize: 9
            font.bold: true
            color: root.playerColor
          }
        }
      }

      // Row 2: Circularity Error % and Center Drift %
      Row {
        width: parent.width
        spacing: Style.space(4)

        // Circularity Error Chip
        Rectangle {
          width: (parent.width - Style.space(4)) / 2
          height: Style.space(26)
          radius: Style.radius(4)
          color: root.chipBackground
          border.color: root.circularityError > 15 ? "#F87171" : root.circularityError > 8 ? "#FBBF24" : root.faintBorder
          border.width: 1

          Column {
            anchors.centerIn: parent
            spacing: 1

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Circularity Error"
              font.family: Style.font.family
              font.pixelSize: 7
              color: root.dimGlyph
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.circularityError.toFixed(1) + "%"
              font.family: Style.font.family
              font.pixelSize: 10
              font.bold: true
              color: root.circularityError > 15 ? "#F87171" : root.circularityError > 8 ? "#FBBF24" : root.playerColor
            }
          }
        }

        // Center Drift Chip
        Rectangle {
          width: (parent.width - Style.space(4)) / 2
          height: Style.space(26)
          radius: Style.radius(4)
          color: root.chipBackground
          border.color: root.centerDriftPercent > 5 ? "#F87171" : root.centerDriftPercent > 2.5 ? "#FBBF24" : root.faintBorder
          border.width: 1

          Column {
            anchors.centerIn: parent
            spacing: 1

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Center Drift"
              font.family: Style.font.family
              font.pixelSize: 7
              color: root.dimGlyph
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.centerDriftPercent.toFixed(1) + "%"
              font.family: Style.font.family
              font.pixelSize: 10
              font.bold: true
              color: root.centerDriftPercent > 5 ? "#F87171" : root.centerDriftPercent > 2.5 ? "#FBBF24" : root.playerColor
            }
          }
        }
      }
    }
  }
}
