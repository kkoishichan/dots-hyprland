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
    readonly property string statePath: FileUtils.trimFileProtocol(Directories.state + "/user/scrolling-workspaces.json")
    readonly property var monitorSnapshots: HyprlandData.monitors.map(m => {
        const live = Hyprland.monitors.values.find(v => v.name === m.name);
        return Object.assign({}, m, { activeWorkspace: { id: live?.activeWorkspace?.id ?? m.activeWorkspace?.id } });
    })

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
        return Hyprland.monitors.values.find(m => m.name === name)?.activeWorkspace?.id
            ?? monitorForName(name)?.activeWorkspace?.id ?? 0;
    }

    function focusedName() {
        return Hyprland.focusedMonitor?.name || monitorSnapshots[0]?.name || "";
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
        const ids = workspaceIds(name);
        const index = Math.max(0, ids.indexOf(activeId(name)));
        focusAt(index + delta + 1, name);
    }

    function moveWindowTo(name, id, address, follow) {
        if (GlobalStates.screenLocked || !WorkspaceModel.validId(id)) return;
        protect(id);
        const selector = address ? `, window = ${luaString("address:" + address)}` : "";
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${id}, follow = false${selector} })`);
        if (follow) focusWorkspace(name, id);
        schedule();
    }

    function sendAt(position, follow) {
        const name = focusedName();
        normalize();
        const ids = workspaceIds(name);
        if (ids.length) moveWindowTo(name, ids[Math.max(0, Math.min(ids.length - 1, position - 1))], "", follow);
    }

    function sendRelative(delta, follow) {
        const name = focusedName();
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
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${luaString(name)} })`);
        Hyprland.dispatch(`hl.dsp.focus({ window = ${luaString("address:" + address)} })`);
    }

    function focusColumn(name, delta) {
        const id = activeId(name);
        const windows = windowsForWorkspace(name, id).filter(w => !w.floating);
        if (!windows.length) return;
        const focused = focusedWindow(name, id);
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${luaString(name)} })`);
        if (focused?.floating) focusWindow(name, (delta < 0 ? windows[windows.length - 1] : windows[0]).address);
        else Hyprland.dispatch(`hl.dsp.layout("focus ${delta < 0 ? "l" : "r"}")`);
    }

    Connections {
        target: HyprlandData
        function onWindowListChanged() { root.schedule(); }
        function onWorkspacesChanged() { root.schedule(); }
        function onMonitorsChanged() { root.schedule(); }
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
