pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import "ScrollingGeometry.js" as Geometry
import "ScrollingWorkspaceModel.js" as WorkspaceModel

Singleton {
    id: root
    property var state: ({ version: 1, orders: {}, homes: {}, nextId: 11 })
    property var pending: ({})
    property bool ready: false
    property var connectedNames: []
    // The window most recently activated from the shell, e.g. an overview selection.
    property string focusRequest: ""
    property bool placingWindow: false
    property var windowInsertions: []
    property var currentInsertion: null
    property var awaitingInsertionSnapshots: []
    property int nextInsertionId: 0
    signal windowInsertionFinished(int requestId, string address, bool success)
    readonly property string statePath: FileUtils.trimFileProtocol(Directories.state + "/user/scrolling-workspaces.json")
    // Native JSON snapshots stay authoritative even if the module's event
    // connection has dropped and its monitor objects are frozen.
    readonly property var monitorSnapshots: HyprlandData.monitors

    function schedule() {
        if (!reconcileTimer.running) reconcileTimer.start();
    }

    function save() {
        if (ready) stateFile.setText(JSON.stringify(state));
    }

    function normalize() {
        if (!ready || GlobalStates.screenLocked || monitorSnapshots.length === 0) return;
        const names = monitorSnapshots.map(m => m.name);
        const returning = names.filter(name => !connectedNames.includes(name));
        const now = Date.now();
        const waiting = {};
        for (const [id, until] of Object.entries(pending)) {
            const confirmed = monitorSnapshots.some(m => m.activeWorkspace?.id === Number(id))
                || HyprlandData.windowList.some(w => w.workspace?.id === Number(id))
                || (HyprlandData.workspaceById[id]?.windows ?? 0) > 0;
            if (until > now && !confirmed) waiting[id] = until;
        }
        root.pending = waiting;
        // Hyprland moves disconnected workspaces to another output. Bring them home on reconnection.
        for (const ws of HyprlandData.workspaces) {
            const home = state.homes[ws.id];
            if (home && returning.includes(home) && ws.monitor !== home && ws.windows > 0) {
                protect(ws.id);
                Hyprland.dispatch(`hl.dsp.workspace.move({ workspace = ${ws.id}, monitor = ${luaString(home)} })`);
            }
        }
        root.connectedNames = names;
        const updated = WorkspaceModel.reconcile(state, monitorSnapshots, HyprlandData.workspaces,
            HyprlandData.windowList, pending, now);
        if (JSON.stringify(updated) !== JSON.stringify(state)) {
            root.state = updated;
            save();
        }
    }

    function luaString(text) {
        return JSON.stringify(String(text));
    }

    function monitorForName(name) {
        return HyprlandData.monitors.find(m => m.name === name) || null;
    }

    function activeId(name) {
        return monitorForName(name)?.activeWorkspace?.id
            ?? Hyprland.monitors.values.find(m => m.name === name)?.activeWorkspace?.id ?? 0;
    }

    function focusedName() {
        return HyprlandData.focusedMonitorName || monitorSnapshots.find(m => m.focused)?.name
            || Hyprland.focusedMonitor?.name || monitorSnapshots[0]?.name || "";
    }

    function workspaceIds(name) {
        return state.orders[name] || [];
    }

    function position(name, id) {
        return workspaceIds(name).indexOf(id) + 1;
    }

    function windowsForWorkspace(name, id) {
        return Geometry.windows(HyprlandData.windowList, id, monitorForName(name));
    }

    function viewport(name) {
        return Geometry.viewport(monitorForName(name));
    }

    function extent(name, windows) {
        return Geometry.extent(windows, monitorForName(name));
    }

    function focusedWindow(name, id) {
        const windows = windowsForWorkspace(name, id);
        if (!windows.length) return null;
        const active = Geometry.address(ToplevelManager.activeToplevel?.HyprlandToplevel?.address);
        const last = Geometry.address(HyprlandData.workspaceById[id]?.lastwindow);
        return windows.find(w => w.address === active) || windows.find(w => w.address === last)
            || windows.reduce((best, w) => (w.focusHistoryID >= 0 && w.focusHistoryID < (best.focusHistoryID < 0 ? Infinity : best.focusHistoryID)) ? w : best, windows[0]);
    }

    function toplevelForAddress(address) {
        return ToplevelManager.toplevels.values.find(t => Geometry.address(t.HyprlandToplevel?.address) === address) || null;
    }

    function protect(id) {
        root.pending = Object.assign({}, pending, { [id]: Date.now() + 1800 });
        pendingTimer.restart();
    }

    function focusWorkspace(name, id) {
        if (GlobalStates.screenLocked || !WorkspaceModel.validId(id)) return;
        protect(id);
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${luaString(name)} })`);
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
        schedule();
    }

    function focusAt(position, name) {
        name = name || focusedName();
        normalize();
        const ids = workspaceIds(name);
        if (ids.length) focusWorkspace(name, ids[Math.max(0, Math.min(ids.length - 1, position - 1))]);
    }

    function focusRelative(delta, name) {
        name = name || focusedName();
        // Count from the current sequence; a stale empty row would shift the target.
        normalize();
        const ids = workspaceIds(name);
        const index = Math.max(0, ids.indexOf(activeId(name)));
        focusAt(index + delta + 1, name);
    }

    function moveWindowTo(name, id, address, follow) {
        if (GlobalStates.screenLocked || !WorkspaceModel.validId(id)) return;
        protect(id);
        const selector = address ? `, window = ${luaString("address:" + address)}` : "";
        // A native follow focuses the moved window; switching afterwards would
        // focus the target workspace's previously focused window instead.
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${id}, follow = ${follow ? "true" : "false"}${selector} })`);
        schedule();
    }

    function insertWindow(name, id, address, anchor, before) {
        if (GlobalStates.screenLocked || !WorkspaceModel.validId(id) || !address) return 0;
        protect(id);
        const command = `require("custom.overview_drop").insert({ monitor = ${luaString(name)}, workspace = ${id}, address = ${luaString(address)}, anchor = ${luaString(anchor || "")}, before = ${before ? "true" : "false"} })`;
        const requestId = ++nextInsertionId;
        windowInsertions = windowInsertions.concat([{
            requestId, command, address, monitor: name, workspace: id, deadline: Date.now() + 5000
        }]);
        startNextInsertion();
        return requestId;
    }

    function startNextInsertion() {
        placingWindow = !!currentInsertion || insertionProcess.running || windowInsertions.length > 0;
        if (!currentInsertion && !insertionProcess.running && windowInsertions.length && !insertionDelay.running)
            insertionDelay.start();
    }

    function cancelInsertion(requestId, notify = false) {
        if (!requestId) return;
        const item = windowInsertions.find(item => item.requestId === requestId)
            ?? awaitingInsertionSnapshots.find(item => item.requestId === requestId)
            ?? (currentInsertion?.requestId === requestId ? currentInsertion : null);
        windowInsertions = windowInsertions.filter(item => item.requestId !== requestId);
        awaitingInsertionSnapshots = awaitingInsertionSnapshots.filter(item => item.requestId !== requestId);
        if (currentInsertion?.requestId === requestId) {
            currentInsertion = null;
            // Stop this IPC client; a compositor operation already applied cannot be undone.
            if (insertionProcess.running) insertionProcess.signal(9);
            HyprlandData.updateLayoutSnapshot();
        }
        startNextInsertion();
        if (item && notify) Qt.callLater(() => windowInsertionFinished(item.requestId, item.address, false));
    }

    function finishInsertionProcess(success) {
        const item = currentInsertion;
        currentInsertion = null;
        if (item) {
            if (success) {
                // Ignore pre-dispatch queries until all three fresh snapshots arrive.
                awaitingInsertionSnapshots = awaitingInsertionSnapshots.concat([
                    Object.assign({}, item, { revisions: HyprlandData.updateLayoutSnapshot() })
                ]);
            } else {
                HyprlandData.updateLayoutSnapshot();
                Qt.callLater(() => windowInsertionFinished(item.requestId, item.address, false));
            }
        }
        schedule();
        startNextInsertion();
    }

    function previewInsertion(name, id, address, targetName) {
        return WorkspaceModel.previewMove(state, monitorSnapshots, HyprlandData.workspaces,
            HyprlandData.windowList, pending, Date.now(), address, id, targetName ?? name).orders[name] ?? workspaceIds(name);
    }

    // The overview releases exclusive keyboard focus before a focus-based
    // layout transaction. Let that layer-surface change reach the compositor.
    Timer {
        id: insertionDelay
        interval: 50
        onTriggered: {
            if (GlobalStates.screenLocked || !root.windowInsertions.length) {
                for (const item of root.windowInsertions.slice()) root.cancelInsertion(item.requestId, true);
                root.startNextInsertion();
                return;
            }
            root.currentInsertion = root.windowInsertions[0];
            insertionProcess.command = ["hyprctl", "dispatch", root.currentInsertion.command];
            root.windowInsertions = root.windowInsertions.slice(1);
            insertionProcess.running = true;
        }
    }
    Process {
        id: insertionProcess
        stdout: StdioCollector { id: insertionOutput; onStreamFinished: {
            if (text.trim() !== "ok") console.warn("[Scrolling] Window insertion:", text.trim());
        } }
        onExited: (exitCode, exitStatus) => {
            root.finishInsertionProcess(exitCode === 0 && insertionOutput.text.trim() === "ok");
        }
        onRunningChanged: {
            // FailedToStart emits runningChanged, but never exited. Defer so a
            // normal exit can finish its collector and clear the current request.
            if (!running && root.currentInsertion) {
                const requestId = root.currentInsertion.requestId;
                Qt.callLater(() => {
                    if (!insertionProcess.running && root.currentInsertion?.requestId === requestId)
                        root.finishInsertionProcess(false);
                });
            }
        }
    }
    Timer {
        interval: 100
        running: root.placingWindow || root.awaitingInsertionSnapshots.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            const requests = root.windowInsertions.concat(root.awaitingInsertionSnapshots,
                root.currentInsertion ? [root.currentInsertion] : []);
            for (const item of requests) if (item.deadline <= now) root.cancelInsertion(item.requestId, true);
        }
    }

    function sendAt(position, follow) {
        const name = focusedName();
        normalize();
        const ids = workspaceIds(name);
        if (ids.length) moveWindowTo(name, ids[Math.max(0, Math.min(ids.length - 1, position - 1))], "", follow);
    }

    function sendRelative(delta, follow) {
        const name = focusedName();
        normalize();
        const ids = workspaceIds(name);
        sendAt(Math.max(0, ids.indexOf(activeId(name))) + delta + 1, follow);
    }

    function reorder(name, id, delta) {
        const ids = workspaceIds(name).slice();
        const from = ids.indexOf(id);
        if (from < 0) return;
        const occupied = HyprlandData.windowList.some(w => w.workspace?.id === id);
        const end = Math.max(0, ids.length - (occupied ? 2 : 1));
        const to = Math.max(0, Math.min(end, from + delta));
        if (from === to) return;
        ids.splice(from, 1);
        ids.splice(to, 0, id);
        root.state = Object.assign({}, state, { orders: Object.assign({}, state.orders, { [name]: ids }) });
        save();
        normalize();
    }

    function insertAbove(name, beforeId) {
        normalize();
        const ids = workspaceIds(name).slice();
        const used = new Set(Object.values(state.orders).reduce((all, ids) => all.concat(ids), []).concat(HyprlandData.workspaceIds));
        let id = state.nextId;
        while (used.has(id)) id++;
        if (!WorkspaceModel.validId(id)) return;
        ids.splice(Math.max(0, ids.indexOf(beforeId)), 0, id);
        root.state = {
            version: 1, nextId: id + 1,
            orders: Object.assign({}, state.orders, { [name]: ids }),
            homes: Object.assign({}, state.homes, { [id]: name })
        };
        protect(id);
        save();
        focusWorkspace(name, id);
    }

    function focusWindow(name, address) {
        if (GlobalStates.screenLocked) return;
        root.focusRequest = address;
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${luaString(name)} })`);
        Hyprland.dispatch(`hl.dsp.focus({ window = ${luaString("address:" + address)} })`);
    }

    function focusColumn(name, delta, workspaceId) {
        const id = workspaceId ?? activeId(name);
        const windows = windowsForWorkspace(name, id).filter(w => !w.floating);
        if (!windows.length) return;
        const focused = focusedWindow(name, id);
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${luaString(name)} })`);
        if (focused?.floating) focusWindow(name, (delta < 0 ? windows[windows.length - 1] : windows[0]).address);
        else Hyprland.dispatch(`hl.dsp.layout("focus ${delta < 0 ? "l" : "r"}")`);
    }

    Connections {
        target: HyprlandData
        function onWindowSnapshotRevisionChanged() { root.finishInsertions(); }
        function onMonitorSnapshotRevisionChanged() { root.finishInsertions(); }
        function onWorkspaceSnapshotRevisionChanged() { root.finishInsertions(); }
        function onWindowListChanged() { root.schedule(); }
        function onWorkspacesChanged() { root.schedule(); }
        function onMonitorsChanged() { root.schedule(); }
    }
    function finishInsertions() {
        const ready = item => item.revisions.windows <= HyprlandData.windowSnapshotRevision
            && item.revisions.monitors <= HyprlandData.monitorSnapshotRevision
            && item.revisions.workspaces <= HyprlandData.workspaceSnapshotRevision;
        const completed = awaitingInsertionSnapshots.filter(ready);
        if (!completed.length) return;
        awaitingInsertionSnapshots = awaitingInsertionSnapshots.filter(item => !ready(item));
        // The row order and geometry must be from the same completed transaction.
        reconcileTimer.stop();
        normalize();
        for (const item of completed) {
            const window = HyprlandData.windowByAddress[item.address];
            const monitor = root.monitorForName(item.monitor);
            const success = item.deadline > Date.now() && window?.workspace?.id === item.workspace && window?.monitor === monitor?.id;
            Qt.callLater(() => root.windowInsertionFinished(item.requestId, item.address, success));
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.schedule(); }
    }
    onMonitorSnapshotsChanged: schedule()

    Timer { id: reconcileTimer; interval: 150; onTriggered: root.normalize() }
    Timer { id: pendingTimer; interval: 1900; onTriggered: root.normalize() }

    FileView {
        id: stateFile
        path: root.statePath
        onLoaded: {
            if (root.ready) return;
            try {
                const saved = JSON.parse(text());
                if (saved.version === 1 && saved.orders && saved.homes) root.state = saved;
            } catch (error) { console.warn("[Scrolling] Invalid saved sequence:", error); }
            root.ready = true;
            root.schedule();
        }
        onLoadFailed: error => {
            root.ready = true;
            if (error !== FileViewError.FileNotFound) console.warn("[Scrolling] Could not load sequence:", error);
            root.schedule();
        }
    }

    IpcHandler {
        target: "scrolling"
        function workspace(position: int): void { root.focusAt(position); }
        function step(delta: int): void { root.focusRelative(delta); }
        function send(position: int): void { root.sendAt(position, false); }
        function sendStep(delta: int): void { root.sendRelative(delta, true); }
        function reorder(delta: int): void { root.reorder(root.focusedName(), root.activeId(root.focusedName()), delta); }
        function insert(): void { root.insertAbove(root.focusedName(), root.activeId(root.focusedName())); }
        function status(): string { return JSON.stringify({ state: root.state, focusedMonitor: root.focusedName(), activeId: root.activeId(root.focusedName()) }); }
    }
}
