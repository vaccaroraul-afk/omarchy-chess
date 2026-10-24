import QtQuick
import "Model.js" as Model

// The 8×8 board. A pure view: the panel hands it the position and the
// highlight state and reacts to presses and drops; nothing here knows the
// rules. Colors and fonts come in as properties so the board also renders
// outside the shell (no qs.* imports).
//
// Input model, lichess-style: a press selects (the panel decides), a drag
// of the selected piece carries it, and the release reports whether the
// pointer travelled. The panel turns press + release into click-to-move.
Item {
  id: root

  property var pieces: ({})
  property bool flipped: false
  property string selected: ""
  property var targets: ({})
  property string lastFrom: ""
  property string lastTo: ""
  property string checkSquare: ""
  property string cursor: ""
  property bool interactive: true

  property color lightColor: "#e8e8e8"
  property color darkColor: "#8a96a8"
  property color lastMoveColor: "#d6c25a"
  property color selectedColor: "#d6c25a"
  property color checkColor: "#d9534f"
  property color cursorColor: "#202020"
  property color targetColor: Qt.rgba(0, 0, 0, 0.28)
  property color whitePiece: "#fafafa"
  property color whiteOutline: "#1c1c1c"
  property color blackPiece: "#1c1c1c"
  property color blackOutline: Qt.rgba(1, 1, 1, 0.45)
  property string pieceFont: "Font Awesome 7 Free"
  property string labelFont: "monospace"

  readonly property real squareSize: Math.floor(Math.min(width, height) / 8)

  // Drag state; dragSquare stays empty until the pointer leaves the slop.
  property string pressSquare: ""
  property string dragSquare: ""
  property point dragPoint: Qt.point(0, 0)

  signal squarePressed(string square)
  signal squareReleased(string from, string to, bool dragged)

  implicitWidth: 512
  implicitHeight: 512

  function squareAt(x, y) {
    var col = Math.floor((x - grid.x) / squareSize)
    var row = Math.floor((y - grid.y) / squareSize)
    if (col < 0 || col > 7 || row < 0 || row > 7) return ""
    return Model.viewSquare(row * 8 + col, flipped)
  }

  function pieceColor(piece) {
    return piece && piece.color === "w" ? whitePiece : blackPiece
  }

  function outlineColor(piece) {
    return piece && piece.color === "w" ? whiteOutline : blackOutline
  }

  Grid {
    id: grid
    anchors.centerIn: parent
    columns: 8
    width: root.squareSize * 8
    height: root.squareSize * 8

    Repeater {
      model: 64

      delegate: Item {
        id: cell
        required property int index
        readonly property string square: Model.viewSquare(index, root.flipped)
        readonly property bool light: Model.isLightSquare(square)
        readonly property var piece: root.pieces[square] || null
        readonly property string target: root.targets[square] || ""
        readonly property bool lastMove: square === root.lastFrom || square === root.lastTo

        width: root.squareSize
        height: root.squareSize

        Rectangle {
          anchors.fill: parent
          color: cell.light ? root.lightColor : root.darkColor
        }

        Rectangle {
          anchors.fill: parent
          color: cell.square === root.selected ? root.selectedColor : root.lastMoveColor
          opacity: cell.square === root.selected ? 0.6 : (cell.lastMove ? 0.42 : 0)
        }

        // The king in check glows from the center out.
        Rectangle {
          anchors.centerIn: parent
          visible: cell.square === root.checkSquare
          width: parent.width * 0.92
          height: width
          radius: width / 2
          color: root.checkColor
          opacity: 0.75
        }

        Text {
          visible: cell.index % 8 === 0
          anchors { left: parent.left; top: parent.top; margins: root.squareSize * 0.05 }
          text: cell.square.charAt(1)
          color: cell.light ? root.darkColor : root.lightColor
          font.family: root.labelFont
          font.pixelSize: Math.max(8, root.squareSize * 0.18)
          font.bold: true
        }

        Text {
          visible: cell.index >= 56
          anchors { right: parent.right; bottom: parent.bottom; margins: root.squareSize * 0.05 }
          text: cell.square.charAt(0)
          color: cell.light ? root.darkColor : root.lightColor
          font.family: root.labelFont
          font.pixelSize: Math.max(8, root.squareSize * 0.18)
          font.bold: true
        }

        Text {
          anchors.centerIn: parent
          visible: cell.piece !== null && cell.square !== root.dragSquare
          text: cell.piece ? Model.GLYPHS[cell.piece.type] : ""
          color: root.pieceColor(cell.piece)
          style: Text.Outline
          styleColor: root.outlineColor(cell.piece)
          font.family: root.pieceFont
          font.weight: Font.Black
          font.pixelSize: Math.round(root.squareSize * (cell.piece && cell.piece.type === "p" ? 0.56 : 0.66))
        }

        Rectangle {
          anchors.centerIn: parent
          visible: cell.target === "move"
          width: root.squareSize * 0.3
          height: width
          radius: width / 2
          color: root.targetColor
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: root.squareSize * 0.03
          visible: cell.target === "capture"
          radius: width / 2
          color: "transparent"
          border.width: Math.max(2, root.squareSize * 0.08)
          border.color: root.targetColor
        }

        Rectangle {
          anchors.fill: parent
          visible: cell.square === root.cursor
          color: "transparent"
          border.width: Math.max(2, Math.round(root.squareSize * 0.05))
          border.color: root.cursorColor
        }
      }
    }
  }

  // The piece under the pointer while dragging.
  Text {
    readonly property var piece: root.dragSquare !== "" ? root.pieces[root.dragSquare] || null : null
    visible: piece !== null
    x: root.dragPoint.x - width / 2
    y: root.dragPoint.y - height / 2
    z: 10
    text: piece ? Model.GLYPHS[piece.type] : ""
    color: root.pieceColor(piece)
    style: Text.Outline
    styleColor: root.outlineColor(piece)
    font.family: root.pieceFont
    font.weight: Font.Black
    font.pixelSize: Math.round(root.squareSize * 0.74)
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: {
      var square = root.squareAt(mouseX, mouseY)
      if (root.dragSquare !== "") return Qt.ClosedHandCursor
      return square !== "" && (root.pieces[square] || root.targets[square]) ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    property point pressPoint: Qt.point(0, 0)

    onPressed: function(mouse) {
      root.pressSquare = root.squareAt(mouse.x, mouse.y)
      root.dragSquare = ""
      pressPoint = Qt.point(mouse.x, mouse.y)
      if (root.pressSquare !== "") root.squarePressed(root.pressSquare)
    }

    onPositionChanged: function(mouse) {
      if (!pressed || root.pressSquare === "") return
      root.dragPoint = Qt.point(mouse.x, mouse.y)
      if (root.dragSquare === "" && root.selected === root.pressSquare) {
        var dx = mouse.x - pressPoint.x
        var dy = mouse.y - pressPoint.y
        if (dx * dx + dy * dy > 36) root.dragSquare = root.pressSquare
      }
    }

    onReleased: function(mouse) {
      var from = root.pressSquare
      var dragged = root.dragSquare !== ""
      root.pressSquare = ""
      root.dragSquare = ""
      if (from !== "") root.squareReleased(from, root.squareAt(mouse.x, mouse.y), dragged)
    }

    onCanceled: {
      root.pressSquare = ""
      root.dragSquare = ""
    }
  }
}
