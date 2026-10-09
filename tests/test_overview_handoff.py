"""Drive the actual overview's MouseArea and workspace handoff offscreen."""

import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / "dots/.config/quickshell/ii"
QS = shutil.which("qs")


@unittest.skipUnless(QS, "Quickshell is needed for the offscreen overview test")
class OverviewHandoffTests(unittest.TestCase):
    def exercise_drop(self, scenario, probe=None):
        cross = scenario.startswith("cross-")
        backend = scenario == "pruned-backend" or scenario.startswith("backend-")
        with tempfile.TemporaryDirectory(prefix="overview-handoff-") as directory:
            base = Path(directory)

            def write(path, text):
                destination = base / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(text)

            for module, names in {
                "": ["GlobalStates"],
                "services": ["HyprlandData", "ScrollingLayout"],
                "modules/common": ["Appearance", "Config", "Directories"],
                "modules/common/functions": ["ColorUtils", "FileUtils"],
            }.items():
                write(f"{module}/qmldir".lstrip("/"), "\n".join(
                    f"singleton {name} 1.0 {name}.qml" for name in names))
            write("GlobalStates.qml", """pragma Singleton
import QtQml
QtObject { property bool overviewOpen: true; property bool screenLocked: false }
""")
            write("modules/common/Appearance.qml", """pragma Singleton
import QtQuick
QtObject {
    property var rounding: ({small: 8, large: 16})
    property var sizes: ({elevationMargin: 4})
    property var colors: ({colBackgroundSurfaceContainer: "#222222", colSurfaceContainerLow: "#333333",
        colLayer1Hover: "#444444", colLayer2Hover: "#555555", colSecondary: "#aaaaaa", colPrimary: "#dddddd"})
    property Component colorMotion: Component { ColorAnimation { duration: 200 } }
    property var animation: ({elementMoveFast: {duration: 200, type: Easing.OutCubic,
        bezierCurve: [], colorAnimation: colorMotion}})
}
""")
            write("modules/common/Config.qml", """pragma Singleton
import QtQml
QtObject { property var options: ({overview: {scale: 0.18}}) }
""")
            write("modules/common/Directories.qml", """pragma Singleton
import QtQml
QtObject { readonly property string state: %s }
""" % json.dumps(str(base / "state")))
            write("modules/common/functions/FileUtils.qml", """pragma Singleton
import QtQml
QtObject { function trimFileProtocol(path) { return path.startsWith("file://") ? path.slice(7) : path; } }
""")
            write("modules/common/functions/ColorUtils.qml", """pragma Singleton
import QtQml
QtObject { function mix(a, b, ratio) { return a; } }
""")
            write("modules/common/widgets/StyledRectangularShadow.qml", """import QtQuick
Item { property var target }
""")
            write("modules/ii/overview/OverviewWindow.qml", """import QtQuick
Rectangle {
    property var windowData; property var toplevel; property var snapshot; property var fallbackSnapshot
    property bool selected: false; property bool hovered: false; property bool pressed: false
    property bool liveCapture: false; property bool capturing: false; property bool captured: true
    property real cornerRadius: 8
    // Identity and the held frame must survive the cross-workspace handoff.
    property string token: Math.random().toString()
    color: "#777777"; radius: cornerRadius
}
""")
            overview = (SOURCE / "modules/ii/overview/ScrollingOverview.qml").read_text()
            for old, new in {
                "import qs\n": 'import "../../../"\n',
                "import qs.services": 'import "../../../services"',
                "import qs.modules.common\n": 'import "../../common"\n',
                "import qs.modules.common.functions": 'import "../../common/functions"',
                "import qs.modules.common.widgets": 'import "../../common/widgets"',
            }.items():
                overview = overview.replace(old, new)
            write("modules/ii/overview/ScrollingOverview.qml", overview)
            write("modules/ii/overview/OverviewDragController.qml", (SOURCE / "modules/ii/overview/OverviewDragController.qml").read_text())
            write("services/ScrollingGeometry.js", (SOURCE / "services/ScrollingGeometry.js").read_text())
            write("services/ScrollingWorkspaceModel.js", (SOURCE / "services/ScrollingWorkspaceModel.js").read_text())
            clients = []
            for address, workspace, index in ([('0xa', 2, 0), ('0xb', 1, 0)]
                    if scenario.startswith("pruned-") or scenario == "cross-pruned" or backend else
                    [('0xa', 1, 0), ('0xb', 1, 1), ('0xc', 1, 2)]):
                clients.append(dict(address=address, workspace={"id": workspace},
                                    at=[4 + index * 904, 4], size=[900, 1072],
                                    monitor=0, mapped=True, hidden=False, floating=False, focusHistoryID=index))
            if scenario.startswith("wide-"):
                clients[0]["size"][0] = 1800
                clients[1]["at"][0] += 900
                clients[2]["at"][0] += 900
            if scenario == "overflow-motion":
                clients = [dict(address=address, workspace={"id": 1}, at=[4 + index * 904, 4],
                                size=[900, 1072], monitor=0, mapped=True, hidden=False, floating=False)
                           for index, address in enumerate(['0xb', '0xc', *[f'0xz{i}' for i in range(7)], '0xa'])]
            if scenario in ("occupied", "wide-occupied", "wide-motion", "overflow-motion", "cancel"):
                clients.append(dict(address="0xd", workspace={"id": 2}, at=[4, 4],
                                    size=[900, 1072], mapped=True, hidden=False, floating=False))
            remote_id = 3 if scenario == "cross-pruned" else 2
            remote_x, remote_y = (200, 900) if scenario == "cross-vertical" else (1600, 0)
            if cross:
                clients.append(dict(address="0xd", workspace={"id": remote_id}, at=[remote_x + 4, remote_y + 4],
                                    size=[1200, 1432], monitor=1, mapped=True, hidden=False, floating=False))
            write("services/HyprlandData.qml", """pragma Singleton
import QtQml
QtObject {
    property var windowList: %s
    readonly property var windowByAddress: windowList.reduce((map, w) => { map[w.address] = w; return map; }, {})
}
""" % json.dumps(clients))
            write("services/ScrollingLayout.qml", """pragma Singleton
import QtQuick
import Quickshell
import "ScrollingGeometry.js" as Geometry
import "ScrollingWorkspaceModel.js" as WorkspaceModel
Singleton {
    id: root
    property var ids: %s
    property var monitor: ({width: 1920, height: 1080, scale: 1})
    property var pending: null
    property int nextInsertionId: 0
    signal windowInsertionFinished(int requestId, string address, bool success)
    function workspaceIds(name) { return ids; }
    function activeId(name) { return 1; }
    function viewport(name) { return Geometry.viewport(monitor); }
    function extent(name, windows) { return Geometry.extent(windows, monitor); }
    function windowsForWorkspace(name, id) { return Geometry.windows(HyprlandData.windowList, id, monitor); }
    function focusedWindow(name, id) { return windowsForWorkspace(name, id)[0] ?? null; }
    function toplevelForAddress(address) { return null; }
    function luaString(text) { return JSON.stringify(text); }
    function previewInsertion(name, id, address) {
        const state = {orders: {[name]: ids}, homes: {}, nextId: Math.max(11, ...ids) + 1};
        const monitors = [{id: 0, name, activeWorkspace: {id: 1}}];
        const workspaces = ids.map(id => ({id, name: String(id), monitor: name}));
        return WorkspaceModel.previewMove(state, monitors, workspaces, HyprlandData.windowList,
            {}, Date.now(), address, id).orders[name];
    }
    function insertWindow(name, id, address, anchor, before) {
        const requestId = ++nextInsertionId;
        pending = {requestId, workspace: id, address, anchor, before}; dispatchDelay.start();
        return requestId;
    }
    function cancelInsertion(requestId) {
        if (pending?.requestId !== requestId) return;
        dispatchDelay.stop(); snapshotDelay.stop(); pending = null;
    }
    Timer {
        id: dispatchDelay; interval: 240
        onTriggered: {
            const moved = HyprlandData.windowByAddress[root.pending.address];
            const source = moved.workspace.id;
            const target = root.pending.workspace;
            const members = HyprlandData.windowList.filter(w => w.workspace.id === target && w.address !== moved.address)
                .sort((a,b) => a.at[0] - b.at[0]);
            const anchor = members.findIndex(w => w.address === root.pending.anchor);
            const slot = anchor < 0 ? members.length : anchor + (root.pending.before ? 0 : 1);
            members.splice(slot, 0, Object.assign({}, moved, {workspace: {id: target}}));
            const positions = {};
            let left = 4;
            members.forEach(w => { positions[w.address] = left; left += w.size[0] + 4; });
            HyprlandData.windowList = HyprlandData.windowList.map(w => positions[w.address] === undefined ? w
                : Object.assign({}, w, {workspace: {id: target}, at: [positions[w.address], 4]}));
            // The dynamic workspace service drops inactive empty source rows and adds a fresh bottom row.
            const occupied = root.ids.filter(id => id === 1 || HyprlandData.windowList.some(w => w.workspace.id === id));
            const previousBottom = root.ids[root.ids.length - 1];
            root.ids = occupied.concat([occupied.includes(previousBottom) ? Math.max(11, ...root.ids) + 1 : previousBottom]);
            snapshotDelay.start();
        }
    }
    Timer { id: snapshotDelay; interval: 120; onTriggered: root.windowInsertionFinished(root.pending.requestId, root.pending.address, true) }
}
""" % json.dumps([1, 2, 11] if scenario in ("occupied", "wide-occupied", "wide-motion", "overflow-motion", "cancel") or scenario.startswith("pruned-") else [1, 11]))
            if cross:
                orders = {"mock": [1, 2, 11] if scenario == "cross-pruned" else [1, 11], "other": [remote_id, 12]}
                monitors = [{"id": 0, "name": "mock", "x": 0, "y": 0, "width": 1920, "height": 1080,
                             "scale": 1, "activeWorkspace": {"id": 1}},
                            {"id": 1, "name": "other", "x": remote_x, "y": remote_y, "width": 2560, "height": 1440,
                             "scale": 1.5 if scenario == "cross-scaled" else 1, "activeWorkspace": {"id": remote_id}}]
                write("services/ScrollingLayout.qml", """pragma Singleton
import QtQuick
import Quickshell
import "ScrollingGeometry.js" as Geometry
import "ScrollingWorkspaceModel.js" as WorkspaceModel
Singleton {
    id: root
    property var orders: %s
    property var monitors: %s
    property var pending: null
    property var predicted: null
    property int nextInsertionId: 0
    signal windowInsertionFinished(int requestId, string address, bool success)
    function workspaceIds(name) { return orders[name] ?? []; }
    function monitor(name) { return monitors.find(m => m.name === name); }
    function activeId(name) { return monitor(name).activeWorkspace.id; }
    function viewport(name) { return Geometry.viewport(monitor(name)); }
    function extent(name, windows) { return Geometry.extent(windows, monitor(name)); }
    function windowsForWorkspace(name, id) { return Geometry.windows(HyprlandData.windowList, id, monitor(name)); }
    function focusedWindow(name, id) { return windowsForWorkspace(name, id)[0] ?? null; }
    function toplevelForAddress(address) { return null; }
    function luaString(text) { return JSON.stringify(text); }
    function forecast(id, address, targetName) {
        const homes = {};
        const workspaces = [];
        for (const [name, ids] of Object.entries(orders)) for (const id of ids) {
            homes[id] = name;
            if (id < 11) workspaces.push({id, name: String(id), monitor: name,
                windows: HyprlandData.windowList.filter(w => w.workspace.id === id).length});
        }
        return WorkspaceModel.previewMove({orders, homes, nextId: 13}, monitors, workspaces,
            HyprlandData.windowList, {}, Date.now(), address, id, targetName).orders;
    }
    function previewInsertion(name, id, address, targetName) { return forecast(id, address, targetName)[name]; }
    function insertWindow(name, id, address, anchor, before) {
        const requestId = ++nextInsertionId;
        predicted = forecast(id, address, name);
        pending = {requestId, name, workspace: id, address, anchor, before}; dispatchDelay.start();
        return requestId;
    }
    function cancelInsertion(requestId) {
        if (pending?.requestId !== requestId) return;
        dispatchDelay.stop(); snapshotDelay.stop(); pending = null;
    }
    Timer {
        id: dispatchDelay; interval: 240
        onTriggered: {
            const moved = HyprlandData.windowByAddress[root.pending.address];
            const sourceMonitor = root.monitors.find(m => m.id === moved.monitor);
            const destination = root.monitor(root.pending.name);
            const target = root.pending.workspace;
            const members = HyprlandData.windowList.filter(w => w.workspace.id === target && w.address !== moved.address)
                .sort((a,b) => a.at[0] - b.at[0]);
            const anchor = members.findIndex(w => w.address === root.pending.anchor);
            const slot = anchor < 0 ? members.length : anchor + (root.pending.before ? 0 : 1);
            members.splice(slot, 0, Object.assign({}, moved, {workspace: {id: target}, monitor: destination.id,
                size: [moved.size[0] * (destination.width / destination.scale) / (sourceMonitor.width / sourceMonitor.scale),
                       moved.size[1] * (destination.height / destination.scale) / (sourceMonitor.height / sourceMonitor.scale)]}));
            const updates = {};
            let left = destination.x + 4;
            members.forEach(w => { updates[w.address] = Object.assign({}, w, {at: [left, destination.y + 4]}); left += w.size[0] + 4; });
            HyprlandData.windowList = HyprlandData.windowList.map(w => updates[w.address] ?? w);
            root.orders = root.predicted;
            snapshotDelay.start();
        }
    }
    Timer { id: snapshotDelay; interval: 120; onTriggered: root.windowInsertionFinished(root.pending.requestId, root.pending.address, true) }
}
""" % (json.dumps(orders), json.dumps(monitors)))
            event_socket = None
            if backend:
                event_socket = socket.socket(socket.AF_UNIX)
                event_socket.bind(str(base / "events.sock"))
                event_socket.listen(2)
                native = {"clients": clients,
                    "monitors": [{"id": 0, "name": "mock", "focused": True, "width": 1920,
                                  "height": 1080, "scale": 1, "activeWorkspace": {"id": 1}}],
                    "workspaces": [{"id": 1, "name": "1", "monitor": "mock", "windows": 1, "lastwindow": "0xb"},
                                   {"id": 2, "name": "2", "monitor": "mock", "windows": 1, "lastwindow": "0xa"}]}
                write("native.json", json.dumps(native))
                if scenario.startswith("backend-"):
                    write("insertion-mode", scenario.removeprefix("backend-"))
                write("state/user/scrolling-workspaces.json", json.dumps({"version": 1,
                    "orders": {"mock": [1, 2, 11]}, "homes": {"1": "mock", "2": "mock", "11": "mock"}, "nextId": 12}))
                write("hyprctl", """#!/usr/bin/env python3
import json, re, sys, time
from pathlib import Path
state_file = Path(__file__).with_name("native.json")
state = json.loads(state_file.read_text())
command = sys.argv[1]
if command == "dispatch":
    mode_file = state_file.with_name("insertion-mode")
    mode = mode_file.read_text() if mode_file.exists() else "normal"
    mode_file.unlink(missing_ok=True)
    time.sleep(20 if mode == "hang" else 1.65 if mode == "slow" else 0.10)
    if mode == "failure":
        print("error: no window")
        sys.exit(1)
    if mode == "noop":
        print("ok")
        sys.exit(0)
    address = re.search(r'address = "([^"]+)"', sys.argv[-1])[1]
    target = int(re.search(r'workspace = (\\d+)', sys.argv[-1])[1])
    source = next(w["workspace"]["id"] for w in state["clients"] if w["address"] == address)
    anchor = re.search(r'anchor = "([^"]*)"', sys.argv[-1])[1]
    before = 'before = true' in sys.argv[-1]
    for window in state["clients"]:
        if window["address"] == address:
            window["workspace"] = {"id": target}
    for id in {source, target}:
        members = sorted((w for w in state["clients"] if w["workspace"]["id"] == id and w["address"] != address), key=lambda w: w["at"][0])
        if id == target:
            dragged = next(w for w in state["clients"] if w["address"] == address)
            slot = next((i + (0 if before else 1) for i,w in enumerate(members) if w["address"] == anchor), len(members))
            members.insert(slot, dragged)
        left = 4
        for w in members:
            w["at"] = [left, 4]
            left += w["size"][0] + 4
    state["workspaces"] = [{"id": id, "name": str(id), "monitor": "mock",
        "windows": sum(w["workspace"]["id"] == id for w in state["clients"])}
        for id in sorted({w["workspace"]["id"] for w in state["clients"]})]
    temporary = state_file.with_suffix(".next")
    temporary.write_text(json.dumps(state))
    temporary.replace(state_file)
    print("ok")
else:
    # Snapshot first, then delay delivery: a pre-dispatch query must remain stale.
    delays = {"clients": 0.08, "monitors": 0.28, "workspaces": 0.36}
    control_file = state_file.with_name("query-control.json")
    control = json.loads(control_file.read_text()) if control_file.exists() else {}
    delays.update(control.get("delays", {}))
    time.sleep(delays.get(command, 0))
    if command in control.get("invalid", []):
        print("invalid snapshot"); sys.exit(1)
    print(json.dumps(state.get(command, {"id": 1} if command == "activeworkspace" else {})))
""")
                (base / "hyprctl").chmod(0o700)
                for name in ("HyprlandData", "ScrollingLayout"):
                    source = (SOURCE / f"services/{name}.qml").read_text()
                    for old, new in {
                        "import qs\n": 'import ".."\n',
                        "import qs.modules.common\n": 'import "../modules/common"\n',
                        "import qs.modules.common.functions": 'import "../modules/common/functions"',
                        '["hyprctl",': '[' + json.dumps(str(base / "hyprctl")) + ',',
                        "path: Hyprland.eventSocketPath": 'path: ' + json.dumps(str(base / "events.sock")),
                    }.items():
                        source = source.replace(old, new)
                    write(f"services/{name}.qml", source)
            shell = """import QtQuick
import QtQuick.Window
import QtTest 1.3
import Quickshell
import Quickshell.Io
import "services"
import "modules/ii/overview"
Scope {
    property bool cross: false
    property var releaseObservation: null
    property bool snapBeforeNative: false
    property var motionFrames: []
    property bool watchingHover: false
    property var hoverFrames: []
    property string watchAddress: "0xd"
    Window {
        x: 0; y: 0; width: 1400; height: 850; visible: true
        ScrollingOverview { id: overview; screen: ({name: "mock", x: 0, y: 0, width: 1400, height: 850});
            dragController: cross ? sharedDrag : null
            x: 40; y: 20; width: implicitWidth; height: implicitHeight }
    }
    OverviewDragController { id: sharedDrag }
    Window {
        x: 1600; y: 0; width: 1600; height: 1100; visible: cross
        ScrollingOverview { id: other; screen: ({name: "other", x: 1600, y: 0, width: 1600, height: 1100});
            dragController: cross ? sharedDrag : null
            x: 40; y: 20; width: implicitWidth; height: implicitHeight }
    }
    TestEvent { id: events }
    function find(item, address) {
        if (item.windowData?.address === address) return item;
        for (const child of item.children) { const result = find(child, address); if (result) return result; }
        return null;
    }
    function hoverSample() {
        const card = find(overview, watchAddress);
        const point = card.mapToItem(overview, 0, 0);
        return {x: point.x, token: card.token, visible: card.visible, shown: card.shown};
    }
    FrameAnimation {
        running: watchingHover
        onTriggered: hoverFrames = hoverFrames.concat([hoverSample()])
    }
    FrameAnimation {
        running: releaseObservation !== null
        onTriggered: {
            const card = sharedDrag.sourceCard ?? find(overview, "0xa") ?? find(other, "0xa");
            if (!card) return;
            const point = card.mapToItem(overview, 0, 0);
            const native = HyprlandData.windowByAddress["0xa"];
            motionFrames = motionFrames.concat([{x: point.x, y: point.y, token: card.token,
                shown: card.shown, visible: card.visible, dragging: card.dragging, dropping: card.dropping,
                nativeWorkspace: native?.workspace?.id, nativeX: native?.at?.[0], overviewHeight: overview.height,
                incoming: other.incomingCard.visible, incomingX: other.incomingCard.mapToItem(overview, 0, 0).x,
                incomingY: other.incomingCard.mapToItem(overview, 0, 0).y,
                incomingWidth: other.incomingCard.width,
                awaiting: ScrollingLayout.awaitingInsertionSnapshots ?? [], revisions: {
                    windows: HyprlandData.windowSnapshotRevision ?? 0,
                    monitors: HyprlandData.monitorSnapshotRevision ?? 0,
                    workspaces: HyprlandData.workspaceSnapshotRevision ?? 0}}]);
            if (card.dropping && !card.dragging && native?.workspace?.id === releaseObservation.workspace && native.at[0] === releaseObservation.nativeX
                && Math.hypot(point.x - releaseObservation.x, point.y - releaseObservation.y) > 2)
                snapBeforeNative = true;
            if (!card.dropping) releaseObservation = null;
        }
    }
    IpcHandler {
        target: "test"
        function focused(): string { return HyprlandData.focusedMonitorName; }
        function complete(requestId: int, address: string, success: bool): void {
            ScrollingLayout.windowInsertionFinished(requestId, address, success);
        }
        function settle(): void { overview.settled = true; other.settled = true; }
        function watchHover(address: string): void { watchAddress = address; hoverFrames = [hoverSample()]; watchingHover = true; }
        function hovered(): string { watchingHover = false; return JSON.stringify(hoverFrames); }
        function scrollEnd(): void {
            const lane = overview.laneForWorkspace(1);
            const tape = lane.children.find(item => item.objectName === "workspaceTape");
            tape.contentX = Math.max(0, tape.contentWidth - tape.width);
        }
        function frames(): string { return JSON.stringify(motionFrames); }
        function status(): string {
            const card = sharedDrag.sourceCard ?? find(overview, "0xa") ?? find(other, "0xa");
            const point = card?.mapToItem(overview, 0, 0);
            return JSON.stringify({x: point?.x, y: point?.y, width: card?.width, height: card?.height,
                token: card?.token, shown: card?.shown, visible: card?.visible, dragging: card?.dragging,
                dropping: card?.dropping, requestId: card?.insertionRequestId,
                placing: ScrollingLayout.placingWindow ?? false, current: ScrollingLayout.currentInsertion ?? null,
                awaiting: ScrollingLayout.awaitingInsertionSnapshots ?? [], queue: ScrollingLayout.windowInsertions ?? [],
                focused: HyprlandData.focusedMonitorName ?? "", monitorRevision: HyprlandData.monitorSnapshotRevision ?? 0,
                snapshotFocus: HyprlandData.monitors?.find(m => m.focused)?.name ?? "",
                workspace: card?.windowData?.workspace?.id, overviewHeight: overview.height,
                nativeWorkspace: HyprlandData.windowByAddress["0xa"]?.workspace?.id,
                nativeX: HyprlandData.windowByAddress["0xa"]?.at?.[0], nativeMonitor: HyprlandData.windowByAddress["0xa"]?.monitor,
                target: cross ? sharedDrag.targetView?.dropTarget ?? null : overview.dropTarget,
                active: sharedDrag.active, targetMonitor: sharedDrag.targetView?.monitorName,
                incoming: other.incomingCard.visible, incomingX: other.incomingCard.mapToItem(overview, 0, 0).x,
                incomingY: other.incomingCard.mapToItem(overview, 0, 0).y,
                remoteIds: other.workspaceIds, remoteRows: other.workspaceIds.map(id => {
                    const lane = other.laneForWorkspace(id); const p = lane.mapToItem(overview, 0, 0);
                    const tape = lane.children.find(item => item.objectName === "workspaceTape");
                    const slot = lane.preview.slot;
                    const slotPoint = slot ? tape.contentItem.mapToItem(overview,
                        (slot.localX - lane.extent.left) * other.previewScale + tape.inset,
                        slot.localY * other.previewScale) : null;
                    return {id, x: p.x, y: p.y, width: lane.width, height: lane.height,
                        slot: slot ? {x: slotPoint.x, width: slot.layoutWidth * other.previewScale} : null,
                        cards: tape.cards.children.filter(item => item.windowData?.address).map(item => {
                            const p = item.mapToItem(overview, 0, 0);
                            return {address: item.windowData.address, x: p.x, width: item.width};
                        })};
                }),
                snapBeforeNative,
                awaiting: ScrollingLayout.awaitingInsertionSnapshots ?? [],
                revisions: {windows: HyprlandData.windowSnapshotRevision ?? 0,
                    monitors: HyprlandData.monitorSnapshotRevision ?? 0,
                    workspaces: HyprlandData.workspaceSnapshotRevision ?? 0},
                ids: overview.workspaceIds, rows: overview.workspaceIds.map(id => {
                    const lane = overview.laneForWorkspace(id); const p = lane.mapToItem(overview, 0, 0);
                    const tape = lane.children.find(item => item.objectName === "workspaceTape");
                    const slot = lane.preview.slot;
                    const slotPoint = slot ? tape.contentItem.mapToItem(overview,
                        (slot.localX - lane.extent.left) * overview.previewScale + tape.inset,
                        slot.localY * overview.previewScale) : null;
                    return {id, x: p.x, y: p.y, width: lane.width, height: lane.height,
                        slot: slot ? {x: slotPoint.x, width: slot.layoutWidth * overview.previewScale} : null,
                        cards: tape.cards.children.filter(item => item.windowData?.address).map(item => {
                            const p = item.mapToItem(overview, 0, 0);
                            return {address: item.windowData.address, x: p.x, width: item.width};
                        })};
                })});
        }
        function press(): void {
            const card = find(overview, "0xa"); const p = card.mapToItem(overview, card.width / 2, card.height / 2);
            events.mousePress(overview, p.x, p.y, Qt.LeftButton, Qt.NoModifier, 0);
            events.mouseMove(overview, p.x + 30, p.y, 0, Qt.LeftButton, Qt.NoModifier);
            events.mouseMove(overview, p.x + 40, p.y, 0, Qt.LeftButton, Qt.NoModifier);
        }
        function move(x: real, y: real): void { events.mouseMove(overview, x, y, 0, Qt.LeftButton, Qt.NoModifier); }
        function refresh(): void { HyprlandData.updateAll(); }
        function release(x: real, y: real): void {
            const card = sharedDrag.sourceCard ?? find(overview, "0xa"); const point = card.mapToItem(overview, 0, 0);
            const native = HyprlandData.windowByAddress["0xa"];
            const start = cross ? other.incomingCard.mapToItem(overview, 0, 0) : point;
            releaseObservation = {x: start.x, y: start.y, nativeX: native.at[0], workspace: native.workspace.id};
            events.mouseRelease(overview, x, y, Qt.LeftButton, Qt.NoModifier, 0);
        }
    }
}
"""
            if cross:
                shell = shell.replace("property bool cross: false", "property bool cross: true")
            if scenario == "cross-vertical":
                shell = shell.replace("x: 1600; y: 0;", "x: 200; y: 900;")
                shell = shell.replace('name: "other", x: 1600, y: 0', 'name: "other", x: 200, y: 900')
            write("shell.qml", shell)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime), NO_COLOR="1")
            for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                env.pop(name, None)
            command = [QS, "-p", str(base / "shell.qml")]

            def rpc(method, *arguments):
                return subprocess.check_output(command + ["ipc", "call", "test", method, *map(str, arguments)],
                                               env=env, text=True, stderr=subprocess.STDOUT, timeout=5).strip()

            def status():
                return json.loads(rpc("status"))

            started = subprocess.run(command + ["-d"], env=env, text=True, capture_output=True, timeout=10)
            try:
                self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
                self.assertIn("Configuration Loaded", started.stdout + started.stderr)
                if backend:
                    time.sleep(0.65)
                else:
                    time.sleep(0.12)
                rpc("settle")
                if scenario == "overflow-motion":
                    rpc("scrollEnd")
                initial = status()
                if probe:
                    probe(base, rpc, status, event_socket)
                    return
                self.assertTrue(initial["visible"])
                target_id = (12 if scenario == "cross-bottom" else remote_id) if cross else 1 if scenario in ("same-workspace", "pruned-occupied", "repeat") else 2 if scenario in ("occupied", "wide-occupied", "wide-motion", "overflow-motion", "cancel") else 11
                row = next(row for row in initial["remoteRows" if cross else "rows"] if row["id"] == target_id)
                # Drop away from the final slot so the return must visibly animate.
                x, y = row["x"] + row["width"] * 0.78, row["y"] + row["height"] * 0.55
                rpc("press")
                if scenario in ("wide-motion", "overflow-motion"):
                    rpc("watchHover", "0xz6" if scenario == "overflow-motion" else "0xd")
                rpc("move", x, y)
                time.sleep(0.28)
                if scenario in ("wide-motion", "overflow-motion"):
                    frames = json.loads(rpc("hovered"))
                    travel = abs(frames[-1]["x"] - frames[0]["x"])
                    self.assertGreater(travel, 20, "The fixture did not make a neighbour yield")
                    step = max(abs(b["x"] - a["x"]) for a, b in zip(frames, frames[1:]))
                    self.assertLess(step, travel * 0.5,
                                    "The centring origin jumped before the avoidance animation: " +
                                    str([round(frame["x"], 2) for frame in frames]))
                    self.assertTrue(all(f["token"] == frames[0]["token"] and f["visible"] and f["shown"] == 1 for f in frames))
                before_release = status()
                self.assertTrue(before_release["dragging"], str(before_release) +
                                subprocess.check_output(command + ["log", "-t", "100"], env=env, text=True))
                self.assertEqual(before_release["target"]["workspace"], target_id)
                receiving = next(row for row in before_release["remoteRows" if cross else "rows"] if row["id"] == target_id)
                slot = receiving["slot"]
                if cross:
                    self.assertTrue(before_release["incoming"])
                    self.assertEqual(before_release["targetMonitor"], "other")
                    self.assertGreater(slot["width"], 0)
                else:
                    self.assertAlmostEqual(slot["width"], before_release["width"], places=3)
                self.assertTrue(all(card["x"] + card["width"] <= slot["x"] + 1 or
                                    card["x"] >= slot["x"] + slot["width"] - 1 for card in receiving["cards"]),
                                "Neighbours did not leave the dragged window's full width: " + str(receiving))
                if scenario in ("cancel", "cross-cancel"):
                    # Releasing outside all lanes restores the source and removes the reserved gap.
                    cancel_x = x if cross else -10
                    cancel_y = row["y"] - 15 if cross else y
                    rpc("move", cancel_x, cancel_y)
                    rpc("release", cancel_x, cancel_y)
                    time.sleep(0.3)
                    restored = status()
                    self.assertFalse(restored["dragging"] or restored["dropping"])
                    self.assertIsNone(restored["target"])
                    self.assertTrue(all(row["slot"] is None for row in restored["rows"]))
                    self.assertAlmostEqual(restored["x"], initial["x"], places=3)
                    self.assertEqual(restored["token"], initial["token"])
                    return
                if backend:
                    rpc("refresh")
                rpc("release", x, y)
                if scenario == "backend-slow":
                    time.sleep(1.55)
                    self.assertTrue(status()["dropping"], "The card timed out before its native placement completed")
                time.sleep(0.9)
                final = status()
                if scenario in ("backend-failure", "backend-noop"):
                    self.assertEqual(final["nativeWorkspace"], initial["nativeWorkspace"])
                    self.assertFalse(final["dragging"] or final["dropping"])
                    self.assertIsNone(final["target"])
                    self.assertTrue(all(row["slot"] is None for row in final["rows"]), "A failed insertion left a reserved gap")
                    self.assertAlmostEqual(final["x"], initial["x"], delta=0.75, msg=json.dumps({"initial": initial, "final": final}))
                    self.assertEqual(final["token"], initial["token"])
                if scenario in ("repeat", "backend-failure", "backend-noop"):
                    # Reuse the actual same MouseArea. Its drag target and bindings
                    # must survive failed drops and multiple workspace handoffs.
                    for step in range(4):
                        state = status()
                        row_id = 1 if scenario == "repeat" or step % 2 else state["ids"][-1]
                        row = next(r for r in state["rows"] if r["id"] == row_id)
                        x = row["x"] + row["width"] * (0.1 if step % 2 else 0.85)
                        y = row["y"] + row["height"] * 0.5
                        rpc("press")
                        rpc("move", x, y)
                        time.sleep(0.24)
                        self.assertEqual(status()["target"]["workspace"], row_id)
                        rpc("release", x, y)
                        time.sleep(0.8)
                        state = status()
                        self.assertEqual(state["nativeWorkspace"], row_id)
                        self.assertFalse(state["dragging"] or state["dropping"])
                        self.assertIsNone(state["target"])
                        self.assertTrue(all(r["slot"] is None for r in state["rows"]))
                        lane = next(r for r in state["rows"] if r["id"] == row_id)
                        cards = sorted(lane["cards"], key=lambda w: w["x"])
                        self.assertIn("0xa", [w["address"] for w in cards], "The returned card kept its old drag parent")
                        if scenario == "repeat":
                            self.assertEqual(cards[0 if step % 2 else -1]["address"], "0xa", "The repeated drag lost the pointer's insertion position")
                        for a, b in zip(cards, cards[1:]):
                            self.assertAlmostEqual(b["x"] - a["x"] - a["width"], 4 * 0.18, delta=0.1,
                                                   msg="A completed move left the dragged column's width empty")
                    return
                samples = json.loads(rpc("frames")) + [final]
                self.assertEqual(final["workspace"], target_id)
                self.assertFalse(final["dropping"])
                self.assertFalse(final["dragging"])
                waiting = [s for s in samples if s["dropping"]]
                self.assertTrue(waiting, "No pending drop frames were rendered")
                continuity = waiting if cross else samples
                self.assertTrue(all(s["token"] == initial["token"] for s in continuity), "The dragged card was recreated")
                self.assertTrue(all(s["visible"] and s["shown"] == 1 for s in continuity), "The held frame faded away")
                self.assertTrue(final["snapBeforeNative"],
                                "The snap waited for the native transaction")
                moving = [s for s in waiting if not s["dragging"]]
                self.assertTrue(any(abs(s["x"] - final["x"]) > 2 and
                                    abs(s["x"] - before_release["x"]) > 2 for s in moving),
                                "The card jumped directly to the final slot: " + json.dumps(
                                    [(round(s["x"], 2), round(s["y"], 2), s["dragging"]) for s in samples]))
                if scenario.startswith("pruned-"):
                    self.assertNotIn(2, final["ids"])
                if cross:
                    self.assertEqual(final["nativeMonitor"], 1)
                    self.assertFalse(final["active"] or final["incoming"])
                    self.assertTrue(all(s["incoming"] for s in waiting), "The cross-screen preview disappeared before handoff")
                    self.assertTrue(all(abs(s["incomingX"] - s["x"]) < 1 and abs(s["incomingY"] - s["y"]) < 1 for s in waiting),
                                    "The destination preview jumped relative to its continuous snap")
                    if scenario == "cross-pruned":
                        self.assertNotIn(2, final["ids"])
                if scenario in ("pruned-source", "pruned-backend"):
                    self.assertLess(final["y"], before_release["y"])
                    path = [before_release, *samples]
                    self.assertTrue(all(b["y"] <= a["y"] + 1 for a, b in zip(path, path[1:])),
                                    "The sole-window drop folded down and then back up: " +
                                    str([round(s["y"], 2) for s in path]))
                if scenario == "pruned-backend":
                    self.assertTrue(any(s["dropping"] and s["nativeWorkspace"] == target_id and
                                        s["awaiting"] and (s["revisions"]["monitors"] < s["awaiting"][0]["revisions"]["monitors"] or
                                        s["revisions"]["workspaces"] < s["awaiting"][0]["revisions"]["workspaces"]) for s in samples),
                                    "The fixture did not deliver staggered post-dispatch snapshots")
                    self.assertFalse(final["awaiting"])
                if scenario == "pruned-occupied":
                    self.assertTrue(any(final["overviewHeight"] + 2 < s["overviewHeight"] < initial["overviewHeight"] - 2
                                        for s in samples), "Removing a row snapped the viewport height")
                logs = subprocess.check_output(command + ["log", "-t", "200"], env=env, text=True)
                self.assertNotIn("TypeError", logs)
                self.assertNotIn("ReferenceError", logs)
                self.assertNotIn("Binding loop", logs)
            finally:
                subprocess.run(command + ["kill"], env=env, capture_output=True, timeout=5)
                if event_socket:
                    event_socket.close()

    def test_cross_workspace_card_continuity(self):
        for scenario in ("same-workspace", "empty", "occupied", "wide-empty", "wide-occupied", "wide-motion", "overflow-motion", "pruned-source", "pruned-occupied", "cancel", "pruned-backend"):
            with self.subTest(scenario=scenario):
                self.exercise_drop(scenario)

    def test_cross_monitor_drag(self):
        for scenario in ("cross-occupied", "cross-bottom", "cross-pruned", "cross-scaled", "cross-vertical", "cross-cancel"):
            with self.subTest(scenario=scenario):
                self.exercise_drop(scenario)

    def test_repeat_and_failed_insertions(self):
        for scenario in ("repeat", "backend-failure", "backend-noop", "backend-slow"):
            with self.subTest(scenario=scenario):
                self.exercise_drop(scenario)


if __name__ == "__main__":
    unittest.main()
