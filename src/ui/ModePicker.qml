import QtQuick
import qs.Commons
import qs.Ui
import "../js/modes.mjs" as Modes

Column {
    id: picker

    required property var bar
    property string current: ""
    readonly property real cellWidth: (width - cells.spacing * (Modes.MODES.length - 1)) / Modes.MODES.length

    signal picked(string mode)

    spacing: Style.space(10)

    PanelSectionHeader {
        text: "FN LOCK"
        foreground: picker.bar.foreground
        fontFamily: picker.bar.fontFamily
    }

    Row {
        id: cells
        width: parent.width
        spacing: Style.space(6)

        Repeater {
            model: Modes.MODES

            Button {
                required property var modelData
                width: picker.cellWidth
                iconText: modelData.icon
                iconSize: Style.font.title
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: picker.bar.foreground
                fontFamily: picker.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: picker.current === modelData.mode
                onClicked: picker.picked(modelData.mode)
            }
        }
    }
}
