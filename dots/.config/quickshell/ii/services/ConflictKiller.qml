pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string killDialogQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("killDialog.qml"))

    function load() {
        // dummy to force init
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) checkConflictsProc.running = true
        }
    }

    Process {
        id: checkConflictsProc
        // Quickshell can use kded6's StatusNotifierWatcher. Its presence is not a conflict.
        command: ["pidof", "mako", "dunst"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length === 0) return;
                if (Config.options.conflictKiller.autoKillNotificationDaemons) {
                    Quickshell.execDetached(["killall", "mako", "dunst"])
                } else {
                    Quickshell.execDetached(["qs", "-p", root.killDialogQmlPath])
                }
            }
        }
    }
}
