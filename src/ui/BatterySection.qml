import QtQuick
import qs.Commons
import qs.Ui
import "../js/status.mjs" as Status

Column {
    id: section

    required property var bar
    property var battery: null
    readonly property bool critical: !!battery && !!battery.critical

    visible: battery !== null
    spacing: Style.space(6)

    Item {
        width: parent.width
        implicitHeight: Math.max(header.implicitHeight, percent.implicitHeight)

        PanelSectionHeader {
            id: header
            text: "BATTERY"
            foreground: section.bar.foreground
            fontFamily: section.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: percent
            textFormat: Text.PlainText
            text: Status.batteryText(section.battery)
            color: section.critical ? section.bar.urgent : Qt.darker(section.bar.foreground, 1.4)
            font.family: section.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    BatteryMeter {
        width: parent.width
        bar: section.bar
        percent: section.battery ? section.battery.percent : 0
        critical: section.critical
    }
}
