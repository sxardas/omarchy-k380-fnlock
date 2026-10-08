import QtQuick
import qs.Commons
import "../js/modes.mjs" as Modes

Item {
    id: hero

    required property var bar
    property string title: ""
    property string status: ""

    implicitHeight: Math.max(logo.implicitHeight, labels.implicitHeight)

    Text {
        id: logo
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: Modes.KEYBOARD_ICON
        color: hero.bar.foreground
        font.family: hero.bar.fontFamily
        font.pixelSize: Style.font.display
    }

    Column {
        id: labels
        anchors.left: logo.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
            textFormat: Text.PlainText
            text: hero.title
            color: hero.bar.foreground
            font.family: hero.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            textFormat: Text.PlainText
            text: hero.status.toUpperCase()
            color: Qt.darker(hero.bar.foreground, 1.4)
            font.family: hero.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width
        }
    }
}
