pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root
    // Settings runs in a separate process: only shell.qml activates the controller.
    property bool controller: false
    readonly property string requestedMode: Config.options.desktopLayout === "classic" ? "classic" : "scrolling"
    property string appliedMode: ""
    onAppliedModeChanged: if (controller) Config.runtimeLayout = appliedMode;
    readonly property bool scrolling: (appliedMode || requestedMode) === "scrolling"
    readonly property bool ready: controller && Config.ready && appliedMode === requestedMode && !process.running && error === ""
    property bool pendingApply: false
    property string error: ""
    property string operation: ""

    function load() {
        controller = true;
        pendingApply = true;
        if (Config.ready) run("query");
    }
    function synchronize() {
        if (!controller || !Config.ready) return;
        if (appliedMode === requestedMode) { pendingApply = false; return; }
        pendingApply = true;
        if (!GlobalStates.screenLocked && !process.running) run(appliedMode ? "reload" : "query");
    }
    function run(kind) {
        error = "";
        operation = kind;
        process.command = kind === "reload" ? ["hyprctl", "reload"] : ["hyprctl", "getoption", "general:layout", "-j"];
        process.running = true;
        watchdog.restart();
    }
    function fail(message) {
        error = message;
        pendingApply = false;
        console.warn("[DesktopLayout]", message);
    }
    onRequestedModeChanged: {
        // Stop all drag transactions before replacing the native algorithm.
        if (controller) GlobalStates.overviewOpen = false;
    }
    Connections {
        target: Config
        // Reload only after the enum has actually reached disk. The native Lua
        // config reads that same file; a fixed delay can race the async writer.
        function onSaved() { root.synchronize(); }
        function onLoaded() { root.synchronize(); }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked && root.pendingApply) root.synchronize();
        }
    }
    Process {
        id: process
        property bool waitingForExit: false
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => {
            waitingForExit = false;
            watchdog.stop();
            if (code !== 0) { root.fail("Could not apply desktop layout: " + (errors.text || output.text).trim()); return; }
            if (root.operation === "reload") { root.run("query"); return; }
            let nativeMode = "";
            try { nativeMode = JSON.parse(output.text).str; } catch (_) {}
            if (nativeMode !== "dwindle" && nativeMode !== "scrolling") {
                root.fail("Unexpected native layout: " + nativeMode);
                return;
            }
            root.appliedMode = nativeMode === "dwindle" ? "classic" : "scrolling";
            root.error = "";
            if (root.pendingApply && root.appliedMode !== root.requestedMode && !GlobalStates.screenLocked) {
                root.pendingApply = false;
                root.run("reload");
            } else if (root.appliedMode === root.requestedMode) root.pendingApply = false;
        }
        onRunningChanged: {
            if (running) waitingForExit = true;
            else Qt.callLater(() => {
                if (!process.running && process.waitingForExit) {
                    process.waitingForExit = false;
                    watchdog.stop();
                    root.fail("hyprctl could not start");
                }
            });
        }
    }
    Timer {
        id: watchdog
        interval: 3000
        onTriggered: {
            process.signal(9);
            root.fail("Timed out applying desktop layout");
        }
    }
    IpcHandler {
        target: "desktopLayout"
        function state(): string {
            return JSON.stringify({ requested: root.requestedMode, applied: root.appliedMode,
                ready: root.ready, error: root.error });
        }
    }
}
