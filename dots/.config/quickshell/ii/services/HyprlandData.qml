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
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})
    property var closedWindowAddresses: ({})

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
        getClients.refresh();
    }

    function updateLayers() {
        getLayers.refresh();
    }

    function updateMonitors() {
        getMonitors.refresh();
    }

    function updateWorkspaces() {
        getWorkspaces.refresh();
        getActiveWorkspace.refresh();
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

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
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
        interval: 30000
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

        function refresh() {
            if (running) refreshPending = true;
            else running = true;
        }

        onExited: {
            if (refreshPending) {
                refreshPending = false;
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
