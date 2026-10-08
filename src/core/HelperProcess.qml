import QtQuick
import Quickshell.Io

// bin/omarchy-k380-fnlock, one request at a time. The latest request wins, except
// that a queued mode switch is never dropped for a plain status read.
Item {
    id: helper

    required property string path
    property string address: ""
    property var queued: null
    property bool answered: false

    signal status(string raw)

    function run(args) {
        if (proc.running) {
            if (!queued || queued[0] === "status" || args[0] !== "status") queued = args
            return
        }
        proc.command = [path].concat(args, address ? ["--address", address] : [])
        answered = false
        proc.running = true
    }

    function answer(raw) {
        answered = true
        status(raw)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: helper.answer(text)
        }
        // A helper that was never built cannot start, and then no stream finishes.
        onRunningChanged: if (!running) silentExit.restart()
        onExited: {
            if (!helper.queued) return
            const next = helper.queued
            helper.queued = null
            Qt.callLater(() => helper.run(next))
        }
    }

    Timer {
        id: silentExit
        interval: 500
        onTriggered: if (!proc.running && !helper.answered) helper.answer("")
    }
}
