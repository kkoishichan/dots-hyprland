pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../services/ScrollingGeometry.js" as Geometry

FocusScope {
    id: root
    required property var screen
    readonly property string monitorName: screen?.name ?? ""
    readonly property var workspaceIds: ScrollingLayout.workspaceIds(monitorName)
    readonly property int activeId: ScrollingLayout.activeId(monitorName)
    readonly property var viewport: ScrollingLayout.viewport(monitorName)
    readonly property real laneGap: 5
    readonly property real windowRadius: Appearance.rounding.small
    readonly property real windowMargin: 4
    readonly property real tapePadding: 8
    readonly property real workspaceRadius: windowRadius + windowMargin
    readonly property real framePadding: 10
    readonly property real verticalPadding: (Appearance.sizes.elevationMargin + framePadding) * 2
    readonly property int visibleLaneCount: Math.min(3, workspaceIds.length)
    readonly property real availableHeight: Math.max(1, (root.QsWindow.window?.height ?? viewport.height) - 120)
    readonly property real previewHeight: Math.max(1, Math.floor(Math.min(260, viewport.height * Config.options.overview.scale,
        (availableHeight - verticalPadding - laneGap * 2) / 3 - windowMargin * 2)))
    readonly property real previewScale: previewHeight / viewport.height
    readonly property real laneHeight: previewHeight + windowMargin * 2
    readonly property real horizontalPadding: verticalPadding + (windowMargin + tapePadding) * 2
    readonly property real defaultWidth: Geometry.overviewWidth([], viewport.width, previewScale, horizontalPadding)
    readonly property var workspaceWidths: workspaceIds.reduce((widths, id) => {
        widths[id] = Geometry.overviewWidth(ScrollingLayout.windowsForWorkspace(monitorName, id),
            viewport.width, previewScale, horizontalPadding);
        return widths;
    }, {})
    property int selectedWorkspace: activeId
    property string selectedAddress: ""
    property int dropWorkspace: -1
    property point dragPoint: Qt.point(0, 0)
    property real dragOriginY: NaN
    // Motion starts after the initial layout, so opening the overview does not animate it.
    property bool settled: false
    // Shared motion for rearranged, returned and dropped cards; it retargets mid-flight.
    readonly property Component moveAnimation: Component { NumberAnimation {
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    } }
    signal searchRequested(string text)
    signal opened()

    implicitWidth: workspaceIds.length ? Math.max(...Object.values(workspaceWidths)) : defaultWidth
    Behavior on implicitWidth { enabled: root.settled; animation: root.moveAnimation.createObject(root) }
    implicitHeight: verticalPadding + visibleLaneCount * laneHeight + Math.max(0, visibleLaneCount - 1) * laneGap

    function selectWorkspace(id) {
        selectedWorkspace = id;
        selectedAddress = ScrollingLayout.focusedWindow(monitorName, id)?.address ?? "";
        const index = workspaceIds.indexOf(id);
        const top = index * (laneHeight + laneGap);
        const current = laneScroll.running ? laneScroll.to : lanes.contentY;
        if (top < current) scrollLanes(top);
        else if (top + laneHeight > current + lanes.height) scrollLanes(top + laneHeight - lanes.height);
    }
    function scrollLanes(target) {
        target = Math.max(0, Math.min(lanes.contentHeight - lanes.height, target));
        laneScroll.stop();
        if (!settled) lanes.contentY = target;
        else if (target !== lanes.contentY) {
            laneScroll.to = target;
            laneScroll.start();
        }
    }
    function geometry() {
        return laneColumn.children.filter(lane => lane.workspaceId !== undefined).map(lane => {
            const origin = lane.mapToGlobal(0, 0);
            const tape = lane.children.find(item => item.objectName === "workspaceTape");
            return { id: lane.workspaceId, x: origin.x, y: origin.y, width: lane.width, height: lane.height,
                windows: tape?.contentItem.children.filter(item => item.windowData !== undefined).map(item => {
                    const point = item.mapToGlobal(0, 0);
                    return { address: item.windowData.address, x: point.x, y: point.y, width: item.width, height: item.height };
                }) ?? [] };
        });
    }
    function activateSelection() {
        GlobalStates.overviewOpen = false;
        if (selectedAddress) ScrollingLayout.focusWindow(monitorName, selectedAddress);
        else ScrollingLayout.focusWorkspace(monitorName, selectedWorkspace);
    }
    function changeWorkspace(delta) {
        const index = workspaceIds.indexOf(selectedWorkspace);
        if (workspaceIds.length) selectWorkspace(workspaceIds[Math.max(0, Math.min(workspaceIds.length - 1, index + delta))]);
    }
    function changeWindow(delta) {
        // Inactive group tabs sit beneath their visible tab, so a selection there would be hidden.
        const windows = ScrollingLayout.windowsForWorkspace(monitorName, selectedWorkspace).filter(w => !w.hidden);
        if (!windows.length) return;
        const index = windows.findIndex(w => w.address === selectedAddress);
        selectedAddress = windows[Math.max(0, Math.min(windows.length - 1, index + delta))].address;
    }
    function wheel(event, tape) {
        laneScroll.stop();
        tape.stopScroll();
        if (event.angleDelta.x || (event.modifiers & Qt.ShiftModifier)) {
            const delta = event.angleDelta.x || event.angleDelta.y;
            tape.contentX = Math.max(0, Math.min(tape.contentWidth - tape.width, tape.contentX - delta));
        } else lanes.contentY = Math.max(0, Math.min(lanes.contentHeight - lanes.height, lanes.contentY - event.angleDelta.y));
        event.accepted = true;
    }
    // Drops are hit-tested by hand so the target follows lanes scrolled under a still pointer.
    function laneAt(point) {
        const lane = laneColumn.children.find(item => item.workspaceId !== undefined
            && item.contains(item.mapFromItem(lanes, point.x, point.y)));
        return lane ? lane.workspaceId : -1;
    }
    function updateDrag(point) {
        dragPoint = point;
        dropWorkspace = laneAt(point);
        if (isNaN(dragOriginY)) dragOriginY = point.y;
        // A card grabbed inside an edge zone must be moved before the lanes start scrolling.
        const edge = 48;
        const armed = Math.abs(point.y - dragOriginY) > 24;
        const depth = point.y < edge ? point.y - edge : point.y > lanes.height - edge ? point.y - lanes.height + edge : 0;
        const reach = armed ? Math.max(-1, Math.min(1, depth / edge)) : 0;
        if (reach !== 0) laneScroll.stop();
        dragScroll.speed = reach * 900;
    }
    function endDrag() {
        dragScroll.speed = 0;
        dragOriginY = NaN;
        dropWorkspace = -1;
    }
    onWorkspaceIdsChanged: {
        if (!workspaceIds.includes(selectedWorkspace)) selectWorkspace(activeId);
    }
    Component.onCompleted: Qt.callLater(() => selectWorkspace(activeId))
    // The overview stays loaded between uses; each opening starts from the current desktop.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            root.settled = false;
            root.endDrag();
            if (!GlobalStates.overviewOpen) return;
            settleTimer.restart();
            root.opened();
            Qt.callLater(() => root.selectWorkspace(root.activeId));
        }
    }
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            if (root.selectedAddress && !HyprlandData.windowByAddress[root.selectedAddress])
                root.selectedAddress = ScrollingLayout.focusedWindow(root.monitorName, root.selectedWorkspace)?.address ?? "";
        }
    }
    function handleNavigation(event) {
        if (event.key === Qt.Key_Escape) GlobalStates.overviewOpen = false;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activateSelection();
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) changeWorkspace(-1);
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) changeWorkspace(1);
        // Qt reports Shift+Tab as Backtab.
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) changeWindow(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) changeWindow(1);
        else if (event.key === Qt.Key_Insert) { ScrollingLayout.insertAbove(monitorName, selectedWorkspace); selectionRestore.restart(); }
        else return false;
        event.accepted = true;
        return true;
    }
    Keys.onPressed: event => {
        if (handleNavigation(event)) return;
        if (event.text && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            && event.text.charCodeAt(0) >= 0x20) searchRequested(event.text);
        else { event.accepted = false; return; }
        event.accepted = true;
    }

    StyledRectangularShadow { target: background }
    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        radius: Appearance.rounding.large + root.framePadding
        color: Appearance.colors.colBackgroundSurfaceContainer

        Flickable {
            id: lanes
            anchors { fill: parent; margins: root.framePadding }
            clip: true
            contentWidth: width
            contentHeight: laneColumn.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: lanes.width
                    height: lanes.height
                    radius: root.workspaceRadius
                    antialiasing: true
                }
            }

            Column {
                id: laneColumn
                width: lanes.width
                spacing: root.laneGap
                Repeater {
                    model: ScriptModel { values: root.workspaceIds.map((id, index) => ({ id, position: index + 1 })); objectProp: "id" }
                    delegate: Rectangle {
                        id: lane
                        required property var modelData
                        readonly property int workspaceId: modelData.id
                        readonly property var windows: ScrollingLayout.windowsForWorkspace(root.monitorName, workspaceId)
                        readonly property var extent: ScrollingLayout.extent(root.monitorName, windows)
                        readonly property real tapeWidth: (extent.right - extent.left) * root.previewScale
                        readonly property bool selected: root.selectedWorkspace === workspaceId
                        readonly property bool receivingDrop: root.dropWorkspace === workspaceId
                        readonly property bool onScreen: y + height > lanes.contentY && y < lanes.contentY + lanes.height
                        width: Math.max(1, (root.workspaceWidths[workspaceId] ?? root.implicitWidth) - root.verticalPadding)
                        x: (laneColumn.width - width) / 2
                        height: root.laneHeight
                        radius: root.workspaceRadius
                        color: receivingDrop ? ColorUtils.mix(Appearance.colors.colSurfaceContainerLow, Appearance.colors.colLayer1Hover, 0.1)
                            : Appearance.colors.colSurfaceContainerLow
                        border.width: 2
                        border.color: selected ? Appearance.colors.colSecondary : receivingDrop ? Appearance.colors.colLayer2Hover : "transparent"
                        Behavior on width { enabled: root.settled; animation: root.moveAnimation.createObject(lane) }
                        Behavior on x { enabled: root.settled; animation: root.moveAnimation.createObject(lane) }
                        Behavior on color { enabled: root.settled; animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(lane) }
                        Behavior on border.color { enabled: root.settled; animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(lane) }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { GlobalStates.overviewOpen = false; ScrollingLayout.focusWorkspace(root.monitorName, lane.workspaceId); }
                        }
                        Flickable {
                            id: tape
                            objectName: "workspaceTape"
                            anchors {
                                fill: parent
                                margins: root.windowMargin
                                leftMargin: root.windowMargin + root.tapePadding
                                rightMargin: root.windowMargin + root.tapePadding
                            }
                            clip: true
                            contentWidth: Math.max(width, lane.tapeWidth)
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: tape.width
                                    height: tape.height
                                    radius: root.windowRadius
                                    antialiasing: true
                                }
                            }
                            readonly property real inset: Math.max(0, (width - lane.tapeWidth) / 2)
                            function centerViewport() {
                                const center = (-lane.extent.left + root.viewport.width / 2) * root.previewScale + inset;
                                contentX = Math.max(0, Math.min(contentWidth - width, center - width / 2));
                            }
                            function revealSelection() {
                                const selected = lane.windows.find(w => w.address === root.selectedAddress);
                                if (!selected || !lane.selected) return;
                                const left = (selected.localX - lane.extent.left) * root.previewScale + inset;
                                const right = left + selected.layoutWidth * root.previewScale;
                                const edgePadding = 4 * root.previewScale;
                                const current = tapeScroll.running ? tapeScroll.to : contentX;
                                let next = current;
                                if (left < current + edgePadding) next = left - edgePadding;
                                else if (right > current + width - edgePadding) next = right - width + edgePadding;
                                next = Math.max(0, Math.min(contentWidth - width, next));
                                tapeScroll.stop();
                                if (!root.settled) contentX = next;
                                else if (next !== contentX) {
                                    tapeScroll.to = next;
                                    tapeScroll.start();
                                }
                            }
                            function stopScroll() { tapeScroll.stop(); }
                            NumberAnimation {
                                id: tapeScroll
                                target: tape
                                property: "contentX"
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                            Component.onCompleted: Qt.callLater(centerViewport)
                            Connections { target: root; function onOpened() { tape.centerViewport(); } }
                            Connections { target: root; function onSelectedAddressChanged() { tape.revealSelection(); } }
                            Repeater {
                                model: ScriptModel { values: lane.windows; objectProp: "address" }
                                delegate: OverviewWindow {
                                    id: window
                                    required property var modelData
                                    readonly property real initialX: (modelData.localX - (lane?.extent?.left ?? 0)) * root.previewScale + (tape?.inset ?? 8)
                                    readonly property real initialY: modelData.localY * root.previewScale
                                    property bool dragging: false
                                    property bool didDrag: false
                                    property Item home: null
                                    // A card dropped on another workspace fades where it was dropped
                                    // until Hyprland reports the move and this lane drops it.
                                    property bool sent: false
                                    property real presence: sent ? 0 : 1
                                    property real shown: 1
                                    windowData: modelData
                                    cornerRadius: root.windowRadius
                                    toplevel: ScrollingLayout.toplevelForAddress(modelData.address)
                                    selected: root.selectedWorkspace === lane.workspaceId && root.selectedAddress === modelData.address
                                    // Only thumbnails in view update live; the rest keep one captured frame.
                                    liveCapture: dragging || lane.onScreen && x + width > tape.contentX && x < tape.contentX + tape.width
                                    x: initialX
                                    y: initialY
                                    width: modelData.layoutWidth * root.previewScale
                                    height: modelData.layoutHeight * root.previewScale
                                    z: dragging ? 100 : modelData.floating ? 3 : modelData.hidden ? 0 : 1
                                    opacity: shown * presence * (modelData.hidden ? 0.45 : 1)
                                    visible: presence > 0
                                    enabled: !sent
                                    // Layout changes glide into place; a dragged card follows the pointer directly.
                                    Behavior on x { enabled: root.settled && !window.dragging; animation: root.moveAnimation.createObject(window) }
                                    Behavior on y { enabled: root.settled && !window.dragging; animation: root.moveAnimation.createObject(window) }
                                    Behavior on width { enabled: root.settled; animation: root.moveAnimation.createObject(window) }
                                    Behavior on height { enabled: root.settled; animation: root.moveAnimation.createObject(window) }
                                    Behavior on presence { animation: root.moveAnimation.createObject(window) }
                                    NumberAnimation {
                                        id: appear
                                        target: window
                                        property: "shown"
                                        from: 0
                                        to: 1
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Easing.OutCubic
                                    }
                                    // Cards arriving while the overview is open, such as a dropped window, fade in.
                                    Component.onCompleted: {
                                        updateCapture();
                                        if (root.settled) appear.start();
                                    }
                                    Connections { target: GlobalStates; function onOverviewOpenChanged() { window.updateCapture(); } }
                                    // Hyprland only copies windows that overlap their monitor. A pending request for a
                                    // column off screen never completes and blocks direct scanout, so a closed overview
                                    // drops those contexts and shows the last snapshot instead. Opening recreates any
                                    // context without a frame, including one stopped by a failed capture.
                                    function updateCapture() {
                                        if (!GlobalStates.overviewOpen) {
                                            capturing = modelData.viewFraction > 0;
                                            if (dragging) returnHome();
                                            return;
                                        }
                                        if (!captured) capturing = false;
                                        capturing = true;
                                    }
                                    function beginDrag() {
                                        const point = window.mapToItem(dragLayer, 0, 0);
                                        home = window.parent;
                                        dragging = true;
                                        window.parent = dragLayer;
                                        window.x = point.x;
                                        window.y = point.y;
                                    }
                                    // Leave the drag layer at the current spot, then glide back into the lane.
                                    function returnHome() {
                                        if (home) {
                                            const point = window.mapToItem(home, 0, 0);
                                            window.parent = home;
                                            window.x = point.x;
                                            window.y = point.y;
                                        }
                                        sent = false;
                                        dragging = false;
                                        x = Qt.binding(() => initialX);
                                        y = Qt.binding(() => initialY);
                                    }
                                    // Bring the card back if the window never left this workspace.
                                    Timer { id: sentTimeout; interval: 1500; onTriggered: window.returnHome() }
                                    MouseArea {
                                        id: windowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        drag.target: window
                                        onEntered: window.hovered = true
                                        onExited: window.hovered = false
                                        onPressed: { window.pressed = true; window.didDrag = false; root.endDrag(); }
                                        onPositionChanged: mouse => {
                                            if (!drag.active) return;
                                            if (!window.dragging) window.beginDrag();
                                            window.didDrag = true;
                                            root.updateDrag(windowArea.mapToItem(lanes, mouse.x, mouse.y));
                                        }
                                        onReleased: {
                                            window.pressed = false;
                                            const target = root.dropWorkspace;
                                            root.endDrag();
                                            if (!window.dragging) return;
                                            if (target > 0 && target !== lane.workspaceId) {
                                                window.sent = true;
                                                sentTimeout.restart();
                                                ScrollingLayout.moveWindowTo(root.monitorName, target, window.modelData.address, false);
                                            } else window.returnHome();
                                        }
                                        onCanceled: { window.pressed = false; root.endDrag(); if (window.dragging) window.returnHome(); }
                                        onClicked: mouse => {
                                            if (window.didDrag) return;
                                            if (mouse.button === Qt.MiddleButton)
                                                Hyprland.dispatch(`hl.dsp.window.close({ window = ${ScrollingLayout.luaString("address:" + window.modelData.address)} })`);
                                            else { GlobalStates.overviewOpen = false; ScrollingLayout.focusWindow(root.monitorName, window.modelData.address); }
                                        }
                                        onWheel: event => root.wheel(event, tape)
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: event => root.wheel(event, tape) }
                        }
                    }
                }
            }
        }
    }
    Item { id: dragLayer; anchors.fill: parent; z: 1000 }
    Timer { id: selectionRestore; interval: 220; onTriggered: root.selectWorkspace(root.activeId) }
    // Dragging near the top or bottom edge scrolls to workspaces outside the three visible lanes,
    // once per rendered frame and faster the closer the pointer is to the edge.
    FrameAnimation {
        id: dragScroll
        property real speed: 0 // px per second
        running: speed !== 0
        onTriggered: {
            const limit = Math.max(0, lanes.contentHeight - lanes.height);
            const next = Math.max(0, Math.min(limit, lanes.contentY + speed * frameTime));
            if (next === lanes.contentY) return;
            lanes.contentY = next;
            root.dropWorkspace = root.laneAt(root.dragPoint);
        }
    }
    NumberAnimation {
        id: laneScroll
        target: lanes
        property: "contentY"
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }
    Timer { id: settleTimer; running: true; interval: 300; onTriggered: root.settled = true }
}
