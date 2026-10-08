import QtQuick
import qs.Commons

Item {
    id: meter

    required property var bar
    property real percent: 0
    property bool critical: false
    readonly property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
    readonly property int tickCount: 11

    implicitHeight: Style.space(22)

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        height: meter.trackHeight
        radius: height / 2
        color: Style.selectedFillFor(meter.bar.foreground, Color.accent)
    }

    Rectangle {
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        height: track.height
        radius: track.radius
        color: meter.critical ? meter.bar.urgent : meter.bar.foreground
        width: track.width * Math.max(0, Math.min(1, meter.percent / 100))

        Behavior on width {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
    }

    Repeater {
        model: meter.tickCount

        Rectangle {
            required property int index
            width: Math.max(1, Style.space(2))
            height: meter.trackHeight + Style.space(4)
            radius: 1
            color: meter.bar.background
            anchors.verticalCenter: track.verticalCenter
            x: track.x + Math.max(0, Math.min(track.width - width,
                track.width * (index / (meter.tickCount - 1)) - width / 2))
        }
    }
}
