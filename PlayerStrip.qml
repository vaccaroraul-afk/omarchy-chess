import QtQuick
import qs.Commons

// One player's line above or below the board: a color dot, the name (bold
// while that side is to move), what they have captured, and their material
// lead when they have one.
Item {
  id: root

  property string side: "w"
  property string name: ""
  property bool moving: false
  property string captures: ""
  property string advantage: ""
  property color foreground: Color.popups.text
  property color dimmed: Util.alpha(foreground, 0.6)
  property string fontFamily: Style.font.family
  property string pieceFont: "Font Awesome 7 Free"

  implicitHeight: Style.space(28)

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.lg

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(10)
      height: width
      radius: width / 2
      color: root.side === "w" ? "#fafafa" : "#1c1c1c"
      border.width: 1
      border.color: Util.alpha(root.foreground, 0.5)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.name
      color: root.moving ? root.foreground : root.dimmed
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.moving
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: text !== ""
      text: root.captures
      color: root.dimmed
      font.family: root.pieceFont
      font.weight: Font.Black
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: text !== ""
      text: root.advantage
      color: root.dimmed
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
