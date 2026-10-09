pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    // Identifies the query that produced this geometry, so a layout transaction
    // can wait for a query started after the compositor finished changing it.
    property int windowSnapshotRevision: 0
    property int monitorSnapshotRevision: 0
    property int workspaceSnapshotRevision: 0
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property string focusedMonitorName: ""
    property var layers: ({})
    property var closedWindowAddresses: ({})
    readonly property bool eventsConnected: eventConnection.item?.connected ?? false

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals

    function setWindowList(windows) {
        const byAddress = {};
        for (const win of windows) byAddress[win.address] = win;
        root.windowByAddress = byAddress;
        root.addresses = windows.map(win => win.address);
        root.windowList = windows;
    }

    function updateWindowList() {
        return getClients.refresh();
    }

    function updateLayers() {
        getLayers.refresh();
    }

    function updateMonitors() {
        return getMonitors.refresh();
    }

    function updateWorkspaces() {
        const revision = getWorkspaces.refresh();
        getActiveWorkspace.refresh();
        return revision;
    }

    function updateLayoutSnapshot() {
        return { windows: updateWindowList(), monitors: updateMonitors(), workspaces: updateWorkspaces() };
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    function handleEvent(event) {
        if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
        if (event.name === "focusedmon") {
            root.focusedMonitorName = event.data.split(",")[0];
        }
        // Layout changes need a notification, without shortcut press/release semantics.
        if (event.name === "custom" && event.data === "ii:layoutChanged") {
            root.updateWindowList();
            return;
        }
        if (event.name === "closewindow" || event.name === "openwindow") {
            const rawAddress = event.data.split(",")[0].trim();
            const address = rawAddress.startsWith("0x") ? rawAddress : `0x${rawAddress}`;
            const closed = Object.assign({}, root.closedWindowAddresses);
            if (event.name === "closewindow") {
                // Do not wait for hyprctl to remove a window that is already gone.
                closed[address] = true;
                root.closedWindowAddresses = closed;
                root.setWindowList(root.windowList.filter(win => win.address !== address));
            } else {
                // Hyprland may reuse an address for a newly opened window.
                delete closed[address];
                root.closedWindowAddresses = closed;
            }
            root.updateWindowList();
        }
        // Bound the wait even when events keep arriving during an animation.
        if (!eventRefresh.running) eventRefresh.start();
    }

    // Quickshell's Hyprland event connection does not reconnect after EOF.
    // Keep snapshot updates alive through a socket we can reconnect, without
    // relying on the native module's cached monitor/workspace objects.
    Loader {
        id: eventConnection
        sourceComponent: Socket {
            path: Hyprland.eventSocketPath
            connected: true
            onConnectedChanged: { if (connected) root.updateAll(); }
            parser: SplitParser {
                onRead: line => {
                    const separator = line.indexOf(">>");
                    if (separator >= 0) root.handleEvent({ name: line.slice(0, separator), data: line.slice(separator + 2) });
                }
            }
        }
    }
    Timer {
        interval: 500
        running: !root.eventsConnected
        repeat: true
        onTriggered: {
            // A failed connection attempt also needs a fresh Socket object.
            eventConnection.active = false;
            eventConnection.active = true;
        }
    }

    // Coalesce event bursts without postponing updates on every new event.
    Timer {
        id: eventRefresh
        interval: 50
        onTriggered: root.updateAll()
    }

    // Recover stale snapshots after missed IPC events or monitor/suspend changes.
    // Every event already refreshes, so this only matters while the desktop is idle.
    Timer {
        interval: root.eventsConnected ? 30000 : 1000
        running: true
        repeat: true
        onTriggered: {
            root.updateWindowList();
            root.updateMonitors();
            root.updateWorkspaces();
        }
    }

    component HyprctlQuery: Process {
        property bool refreshPending: false
        property int requestedRevision: 0
        property int runningRevision: 0

        function refresh() {
            requestedRevision++;
            if (running) refreshPending = true;
            else {
                runningRevision = requestedRevision;
                running = true;
            }
            return requestedRevision;
        }

        onExited: {
            if (refreshPending) {
                refreshPending = false;
                runningRevision = requestedRevision;
                running = true;
            }
        }
    }

    HyprctlQuery {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                const windows = JSON.parse(clientsCollector.text);
                const closed = {};
                for (const win of windows) {
                    if (root.closedWindowAddresses[win.address]) closed[win.address] = true;
                }
                // An in-flight query can finish with a pre-close snapshot. Keep
                // suppressing that address until a later query confirms removal.
                root.closedWindowAddresses = closed;
                root.setWindowList(windows.filter(win => !closed[win.address]));
                root.windowSnapshotRevision = getClients.runningRevision;
            }
        }
    }

    HyprctlQuery {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = JSON.parse(monitorsCollector.text);
                root.focusedMonitorName = root.monitors.find(m => m.focused)?.name ?? "";
                root.monitorSnapshotRevision = getMonitors.runningRevision;
            }
        }
    }

    HyprctlQuery {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    HyprctlQuery {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                var rawWorkspaces = JSON.parse(workspacesCollector.text);
                // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id < 1000000);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
                root.workspaceSnapshotRevision = getWorkspaces.runningRevision;
            }
        }
    }

    HyprctlQuery {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
            }
        }
    }
}
