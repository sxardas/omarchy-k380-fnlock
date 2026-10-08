import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Commons
import qs.Ui
import "core"
import "ui"
import "js/keyboard.mjs" as Keyboard
import "js/modes.mjs" as Modes
import "js/status.mjs" as Status

// The K380 forgets its Fn lock when it powers off, so the mode picked here is
// kept in shell.json and written back each time it reconnects.
Panel {
    id: root
    moduleName: "io.github.sxardas.omarchy-k380-fnlock"
    // A short target is easier to bind to a key; this panel owns the handler.
    ipcTarget: "omarchy-k380-fnlock"
    manageIpc: false

    readonly property string configuredAddress: String(setting("address", "")).trim()
    readonly property string preferredMode: Modes.normalizeMode(setting("mode", ""))
    readonly property bool showLabel: setting("showLabel", false) === true
    readonly property int refreshIntervalSec: Status.refreshInterval(setting("refreshIntervalSec"))

    readonly property var device: Keyboard.findKeyboard(Bluetooth.devices ? Bluetooth.devices.values : [], configuredAddress)
    readonly property bool connected: !!(device && device.connected)

    property var status: ({})
    property bool statusLoaded: false
    property string pendingMode: ""
    property bool appliedThisConnection: false
    property int retriesLeft: 0

    readonly property string keyboardMode: connected ? Modes.normalizeMode(status.mode) : ""

    readonly property string shownMode: pendingMode || keyboardMode || preferredMode
    readonly property string errorKind: connected && statusLoaded ? String(status.error || "") : ""
    readonly property bool needsSetup: Status.needsSetup(errorKind)
    readonly property var battery: connected ? Status.batteryOf(status, device) : null

    function refresh() {
        if (connected) helper.run(["status"])
    }

    // Saved even while the keyboard is away, so it lands on the next connect.
    function set(mode) {
        mode = Modes.normalizeMode(mode)
        if (!mode) return
        if (mode !== preferredMode) {
            root.settings = Object.assign({}, root.settings, {mode: Modes.modeLabel(mode)})
            if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
        }
        if (!connected) return
        appliedThisConnection = true
        if (mode === keyboardMode && !pendingMode) return
        pendingMode = mode
        helper.run(["set", mode])
    }

    // Overrides the base Panel's open/close toggle; that one is toggleWidget here.
    function toggle() {
        set(Modes.otherMode(shownMode || Modes.MEDIA))
    }

    function toggleWidget() {
        opened ? close() : open()
    }

    // `omarchy plugin add` only clones: this builds the helper and installs the udev rule.
    function finishSetup() {
        if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation "
            + Util.shellQuote(Keyboard.localPath(Qt.resolvedUrl("../install.sh"))) + " --setup")
        close()
    }

    function handleStatus(raw) {
        const parsed = Status.parseStatus(raw)
        const wasSwitch = pendingMode !== ""
        pendingMode = ""
        status = parsed
        statusLoaded = true

        if (Status.isTransient(parsed.error) && retriesLeft > 0) {
            retriesLeft--
            retryTimer.restart()
            return
        }
        retriesLeft = 0

        // Once per connection, so a keyboard that ignores the write is not asked on every poll.
        const mode = Modes.normalizeMode(parsed.mode)
        if (!wasSwitch && mode && preferredMode && mode !== preferredMode && !appliedThisConnection) {
            appliedThisConnection = true
            pendingMode = preferredMode
            helper.run(["set", preferredMode])
        }
    }

    onConnectedChanged: {
        if (connected) {
            appliedThisConnection = false
            retriesLeft = 6
            retryTimer.restart()
        } else {
            close()
            status = ({})
            statusLoaded = false
            pendingMode = ""
            retryTimer.stop()
        }
    }

    onOpenedChanged: {
        if (!opened) return
        if (!connected) {
            close()
            return
        }
        refresh()
    }

    Component.onCompleted: if (connected) {
        retriesLeft = 3
        refresh()
    }

    visible: connected
    implicitWidth: connected ? button.implicitWidth : 0
    implicitHeight: connected ? button.implicitHeight : 0

    HelperProcess {
        id: helper
        path: Keyboard.localPath(Qt.resolvedUrl("../bin/omarchy-k380-fnlock"))
        address: root.configuredAddress || (root.device ? String(root.device.address || "") : "")
        onStatus: raw => root.handleStatus(raw)
    }

    // The hidraw node trails BlueZ's Connected by a moment.
    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.opened ? 5000 : root.refreshIntervalSec * 1000
        running: root.connected
        repeat: true
        onTriggered: root.refresh()
    }

    IpcHandler {
        target: "omarchy-k380-fnlock"

        function open(): void {
            root.open()
        }

        function close(): void {
            root.close()
        }

        function show(): void {
            root.open()
        }

        function hide(): void {
            root.close()
        }

        function toggleWidget(): void {
            root.toggleWidget()
        }

        function toggle(): void {
            root.toggle()
        }

        function set(mode: string): void {
            root.set(mode)
        }

        function refresh(): void {
            root.refresh()
        }

        function mode(): string {
            return root.shownMode
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        readonly property bool withLabel: root.showLabel && !vertical && root.shownMode !== ""
        text: Modes.barText(root.shownMode, withLabel)
        slotSize: Style.bar.iconSlot * (withLabel ? 2.4 : 1)
        tooltipText: root.opened ? "" : Status.tooltip(Keyboard.deviceName(root.device), root.shownMode, root.battery)
        onPressed: function (b) {
            if (b === Qt.RightButton) root.toggle()
            else root.toggleWidget()
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened && root.connected
        contentWidth: panel.fittedContentWidth(Style.space(380))
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(14)

            HeroHeader {
                width: parent.width
                bar: root.bar
                title: Keyboard.deviceName(root.device)
                status: Status.statusTitle({
                    loaded: root.statusLoaded, error: root.errorKind, mode: root.keyboardMode
                })
            }

            PanelSeparator {
                visible: root.battery !== null
                foreground: root.bar.foreground
            }

            BatterySection {
                width: parent.width
                bar: root.bar
                battery: root.battery
            }

            PanelSeparator {
                foreground: root.bar.foreground
            }

            ModePicker {
                width: parent.width
                bar: root.bar
                current: root.shownMode
                onPicked: mode => root.set(mode)
            }

            SetupNotice {
                width: parent.width
                bar: root.bar
                text: Status.errorText(root.errorKind, root.status.hidraw)
                showSetup: root.needsSetup
                onSetupClicked: root.finishSetup()
            }
        }
    }
}
