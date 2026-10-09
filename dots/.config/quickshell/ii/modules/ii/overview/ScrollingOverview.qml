pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
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
    property var dragController: null
    readonly property real moveDuration: Appearance.animation.elementMoveFast.duration
    readonly property var dropView: dragController?.targetView ?? root
    readonly property alias incomingCard: externalCard
    readonly property string monitorName: screen?.name ?? ""
    readonly property var nativeWorkspaceIds: ScrollingLayout.workspaceIds(monitorName)
    readonly property var workspaceIds: pendingDrop?.workspaceIds ?? nativeWorkspaceIds
    readonly property var cardAddresses: Array.from(new Set(nativeWorkspaceIds.reduce((addresses, id) => addresses.concat(
        ScrollingLayout.windowsForWorkspace(monitorName, id).map(window => window.address)), []).concat(
            dragController?.sourceView === root && dragController.address ? [dragController.address] : []))).sort()
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
        widths[id] = Geometry.overviewWidth(previewLayouts[id]?.windows ?? [],
            viewport.width, previewScale, horizontalPadding);
        return widths;
    }, {})
    readonly property var previewLayouts: workspaceIds.reduce((layouts, id) => {
        layouts[id] = pendingDrop?.layouts[id] ?? Geometry.dragPreview(
            ScrollingLayout.windowsForWorkspace(monitorName, id), id, draggedWindowData, dropTarget, viewport.width);
        return layouts;
    }, {})
    property int selectedWorkspace: activeId
    property string selectedAddress: ""
    property int dropWorkspace: -1
    property var dropTarget: null
    property string draggedAddress: ""
    property var draggedWindowData: null
    property var pendingDrop: null
    property bool pointerDragging: false
    property Item dragTape: null
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
    Behavior on implicitHeight { enabled: root.settled; animation: root.moveAnimation.createObject(root) }

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
    function laneForWorkspace(id) {
        return laneColumn.children.find(lane => lane.workspaceId === id) ?? null;
    }
    function acceptsGlobalPoint(point) {
        const output = root.QsWindow.window?.screen ?? screen;
        return (root.QsWindow.window?.visible ?? true) && point.x >= output.x && point.y >= output.y
            && point.x < output.x + output.width && point.y < output.y + output.height;
    }
    // These items have no scale/rotation. Read every parent offset so animated
    // recentering invalidates cross-window coordinate bindings, too.
    function globalOrigin(item) {
        let x = 0, y = 0;
        while (item.parent) { x += item.x; y += item.y; item = item.parent; }
        return item.mapToGlobal(x, y);
    }
    function toGlobal(item, x, y) {
        const origin = globalOrigin(item);
        return Qt.point(origin.x + x, origin.y + y);
    }
    function fromGlobal(item, point) {
        const origin = globalOrigin(item);
        return Qt.point(point.x - origin.x, point.y - origin.y);
    }
    function dragPointFromGlobal(point) { return fromGlobal(lanes, point); }
    function setSharedDrag(address, data) {
        clearDragState();
        draggedAddress = address;
        draggedWindowData = data;
    }
    function clearDropTarget() {
        stopDragMotion();
        dropWorkspace = -1;
        dropTarget = null;
        dragTape = null;
    }
    function dropGlobalPosition(id) {
        const lane = laneForWorkspace(id);
        const tape = lane?.children.find(item => item.objectName === "workspaceTape");
        const slot = lane?.preview.slot;
        if (!tape || !slot) return null;
        return toGlobal(root, background.x + lanes.x + lane.x + tape.x - tape.contentX
            + (slot.localX - lane.extent.left) * previewScale + tape.inset,
            background.y + lanes.y + workspaceIds.indexOf(id) * (laneHeight + laneGap)
            + tape.y - lanes.contentY + slot.localY * previewScale);
    }
    function geometry() {
        const viewport = lanes.mapToGlobal(0, 0);
        return laneColumn.children.filter(lane => lane.workspaceId !== undefined).map(lane => {
            const origin = lane.mapToGlobal(0, 0);
            const tape = lane.children.find(item => item.objectName === "workspaceTape");
            return { id: lane.workspaceId, x: origin.x, y: origin.y, width: lane.width, height: lane.height,
                visibleTop: Math.max(origin.y, viewport.y), visibleBottom: Math.min(origin.y + lane.height, viewport.y + lanes.height),
                windows: tape?.cards.children.filter(item => item.windowData?.address).map(item => {
                    const point = item.mapToGlobal(0, 0);
                    return { address: item.windowData.address, x: point.x, y: point.y, width: item.width, height: item.height,
                        captured: item.captured, snapshot: !!item.snapshot };
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
        if (point.x < 0 || point.x > lanes.width || point.y < 0 || point.y > lanes.height) return null;
        const lane = laneColumn.children.find(item => item.workspaceId !== undefined
            && item.contains(item.mapFromItem(lanes, point.x, point.y)));
        return lane ?? null;
    }
    function updateDrop() {
        const lane = laneAt(dragPoint);
        dropWorkspace = lane?.workspaceId ?? -1;
        dragTape = lane?.children.find(item => item.objectName === "workspaceTape") ?? null;
        if (!dragTape) { dropTarget = null; dragScroll.horizontalSpeed = 0; return; }
        const point = dragTape.cards.mapFromItem(lanes, dragPoint.x, dragPoint.y);
        const localX = point.x / previewScale + lane.extent.left;
        // Hit-test the cards where they are currently drawn, including halfway
        // through a layout animation, rather than their final Hyprland positions.
        const cards = dragTape.cards.children.reduce((result, item) => {
            if (item.windowData?.address) result[item.windowData.address] = item;
            return result;
        }, {});
        const windows = lane.preview.windows.map(window => {
            const card = cards[window.address];
            return !card ? window : Object.assign({}, window, {
                localX: card.x / previewScale + lane.extent.left,
                layoutWidth: card.width / previewScale
            });
        });
        const slot = lane.preview.slot;
        // Hold the current slot while the pointer is in its reserved width.
        // Otherwise cards yielding beneath a still pointer can flip the target back and forth.
        if (!slot || localX < slot.localX || localX > slot.localX + slot.layoutWidth) {
            const target = Geometry.insertion(windows, draggedAddress, localX);
            if (dropTarget?.workspace !== lane.workspaceId || dropTarget.anchor !== target.anchor || dropTarget.before !== target.before)
                dropTarget = { workspace: lane.workspaceId, anchor: target.anchor, before: target.before };
        }
        const viewportPoint = dragTape.mapFromItem(lanes, dragPoint.x, dragPoint.y);
        const edge = Math.min(48, dragTape.width / 4);
        const depth = viewportPoint.x < edge ? viewportPoint.x - edge
            : viewportPoint.x > dragTape.width - edge ? viewportPoint.x - dragTape.width + edge : 0;
        dragScroll.horizontalSpeed = Math.max(-1, Math.min(1, depth / edge)) * 700;
        if (dragScroll.horizontalSpeed !== 0) dragTape.stopScroll();
    }
    function updateDrag(point) {
        if (dragController?.sourceView === root) {
            dragController.update(lanes.mapToGlobal(point.x, point.y));
            return;
        }
        updateDragLocal(point);
    }
    function updateDragLocal(point) {
        pointerDragging = true;
        dragPoint = point;
        updateDrop();
        if (isNaN(dragOriginY)) dragOriginY = point.y;
        // A card grabbed inside an edge zone must be moved before the lanes start scrolling.
        const edge = 48;
        const armed = Math.abs(point.y - dragOriginY) > 24;
        const depth = point.y < edge ? point.y - edge : point.y > lanes.height - edge ? point.y - lanes.height + edge : 0;
        const reach = armed ? Math.max(-1, Math.min(1, depth / edge)) : 0;
        if (reach !== 0) laneScroll.stop();
        dragScroll.speed = reach * 900;
    }
    function stopDragMotion() {
        dragScroll.speed = 0;
        dragScroll.horizontalSpeed = 0;
        pointerDragging = false;
        dragOriginY = NaN;
    }
    function commitDrop(target) {
        // Freeze the prediction until the post-placement snapshot arrives. Intermediate
        // native focus/geometry updates must not send the card to a different slot.
        const ids = ScrollingLayout.previewInsertion(monitorName, target.workspace, draggedAddress, target.monitor ?? monitorName);
        const receiving = (target.monitor ?? monitorName) === monitorName ? target : null;
        const layouts = ids.reduce((result, id) => {
            result[id] = Geometry.dragPreview(ScrollingLayout.windowsForWorkspace(monitorName, id),
                id, draggedWindowData, receiving, viewport.width);
            return result;
        }, {});
        pendingDrop = Object.assign({}, target, { address: draggedAddress, layouts, workspaceIds: ids });
        stopDragMotion();
    }
    function endDrag() {
        if (dragController?.active) { dragController.finish(); return; }
        clearDragState();
    }
    function clearDragState() {
        stopDragMotion();
        dropWorkspace = -1;
        dropTarget = null;
        pendingDrop = null;
        dragTape = null;
        draggedAddress = "";
        draggedWindowData = null;
    }
    onWorkspaceIdsChanged: {
        if (!workspaceIds.includes(selectedWorkspace)) selectWorkspace(activeId);
    }
    Component.onCompleted: {
        dragController?.registerView(root);
        Qt.callLater(() => selectWorkspace(activeId));
    }
    Component.onDestruction: dragController?.unregisterView(root)
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
            root.dragController?.pruneSnapshots(HyprlandData.windowList.map(window => window.address));
            if (root.draggedAddress && !HyprlandData.windowByAddress[root.draggedAddress]) root.endDrag();
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

            Item {
                id: laneColumn
                width: lanes.width
                implicitHeight: Math.max(0, root.workspaceIds.length * (root.laneHeight + root.laneGap) - root.laneGap)
                Repeater {
                    model: ScriptModel { values: root.workspaceIds }
                    delegate: Rectangle {
                        id: lane
                        required property int modelData
                        readonly property int workspaceId: modelData
                        readonly property var windows: ScrollingLayout.windowsForWorkspace(root.monitorName, workspaceId)
                        readonly property var windowByAddress: windows.reduce((result, w) => { result[w.address] = w; return result; }, {})
                        readonly property var preview: root.previewLayouts[workspaceId] ?? ({ windows: [], slot: null })
                        readonly property var positionByAddress: preview.windows.reduce((result, w) => { result[w.address] = w; return result; }, {})
                        readonly property var extent: ScrollingLayout.extent(root.monitorName, preview.windows)
                        readonly property real tapeWidth: (extent.right - extent.left) * root.previewScale
                        readonly property bool selected: root.selectedWorkspace === workspaceId
                        readonly property bool receivingDrop: root.dropWorkspace === workspaceId
                        readonly property bool onScreen: y + height > lanes.contentY && y < lanes.contentY + lanes.height
                        width: Math.max(1, (root.workspaceWidths[workspaceId] ?? root.implicitWidth) - root.verticalPadding)
                        // Widths already animate. Derive the centre directly;
                        // animating x again can retain a recycled row's old offset.
                        x: (laneColumn.width - lane.width) / 2
                        y: root.workspaceIds.indexOf(workspaceId) * (root.laneHeight + root.laneGap)
                        height: root.laneHeight
                        radius: root.workspaceRadius
                        color: receivingDrop ? ColorUtils.mix(Appearance.colors.colSurfaceContainerLow, Appearance.colors.colLayer1Hover, 0.1)
                            : Appearance.colors.colSurfaceContainerLow
                        border.width: 2
                        border.color: selected ? Appearance.colors.colSecondary : receivingDrop ? Appearance.colors.colLayer2Hover : "transparent"
                        Behavior on width { enabled: root.settled; animation: root.moveAnimation.createObject(lane) }
                        // Explicit positions retain their bindings when a failed
                        // prediction removes and then recreates a workspace row.
                        Behavior on y { enabled: root.settled; animation: root.moveAnimation.createObject(lane) }
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
                            contentWidth: Math.max(width, cardContainer.width)
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
                            readonly property real inset: cardContainer.x
                            readonly property alias cards: cardContainer
                            // Animate the occupied span as well as column offsets. Using the
                            // final span here would jump the common origin (and scroll bounds)
                            // before the cards have begun yielding to the reserved width.
                            Item {
                                id: cardContainer
                                parent: tape.contentItem
                                x: Math.max(0, (tape.width - width) / 2)
                                width: lane.tapeWidth
                                height: tape.height
                                Behavior on width { enabled: root.settled; animation: root.moveAnimation.createObject(cardContainer) }
                            }
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
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: event => root.wheel(event, tape) }
                        }
                    }
                }
            }
        }
    }
    Instantiator {
        // A window keeps its card across workspace moves, including its capture.
        // Sorting identities avoids model moves when only its workspace changes.
        model: ScriptModel { values: root.cardAddresses }
        delegate: OverviewWindow {
            id: window
            required property string modelData
            readonly property var lane: root.laneForWorkspace(HyprlandData.windowByAddress[modelData]?.workspace?.id ?? 0)
            readonly property var tape: lane?.children.find(item => item.objectName === "workspaceTape") ?? null
            readonly property var layoutData: lane?.windowByAddress[modelData] ?? null
            readonly property var positionData: lane?.positionByAddress[modelData] ?? layoutData
            readonly property var dropGlobal: root.dropView.dropGlobalPosition(root.pendingDrop?.workspace ?? 0)
            readonly property var dropPosition: dropGlobal
                ? root.fromGlobal(dragLayer, dropGlobal) : Qt.point(dragX, dragY)
            property var lastWindowData: null
            parent: dragging || dropping ? dragLayer : tape?.cards ?? dragLayer
            onLayoutDataChanged: { if (layoutData && !dragging && !dropping) lastWindowData = layoutData; }
            readonly property real initialX: ((positionData?.localX ?? 0) - (lane?.extent?.left ?? 0)) * root.previewScale
            readonly property real initialY: (positionData?.localY ?? 0) * root.previewScale
            property bool dragging: false
            property bool dropping: false
            property bool snapping: false
            property bool relocating: false
            property bool placementConfirmed: false
            property bool snapFinished: false
            property int insertionRequestId: 0
            property bool positioned: false
            property bool atHome: true
            property real dragX: 0
            property real dragY: 0
            property bool didDrag: false
            property real shown: 1
            readonly property bool receivingExternal: root.dragController?.active
                && root.dragController.sourceView !== root && root.dragController.address === modelData
            windowData: dragging || dropping ? lastWindowData : layoutData
            cornerRadius: root.windowRadius
            toplevel: ScrollingLayout.toplevelForAddress(modelData)
            fallbackSnapshot: root.dragController?.snapshots[modelData]
                ?? (receivingExternal ? root.dragController.sourceCard?.snapshot ?? null : null)
            onSnapshotChanged: {
                if (windowData?.address === modelData) root.dragController?.rememberSnapshot(modelData, snapshot);
            }
            selected: root.selectedWorkspace === lane?.workspaceId && root.selectedAddress === modelData
            // Only thumbnails in view update live; the rest keep one captured frame.
            liveCapture: dragging || dropping || (lane?.onScreen ?? false) && tape
                && x + tape.inset + width > tape.contentX && x + tape.inset < tape.contentX + tape.width
            // Suspend home coordinates throughout the drag and
            // pending drop. MouseArea can retain the original
            // bindings, so imperative writes alone are not enough.
            x: atHome ? initialX : snapping ? dropPosition.x : dragX
            y: atHome ? initialY : snapping ? dropPosition.y : dragY
            width: (windowData?.layoutWidth ?? 1) * (dropping ? root.dropView.previewScale : root.previewScale)
            height: (windowData?.layoutHeight ?? 1) * (dropping ? root.dropView.previewScale : root.previewScale)
            z: dragging || dropping ? 100 : windowData?.floating ? 3 : windowData?.hidden ? 0 : 1
            opacity: receivingExternal ? 0 : shown * (windowData?.hidden ? 0.45 : 1)
            visible: windowData !== null
            enabled: !dropping && root.pendingDrop === null
                && (!root.dragController?.active || root.dragController.sourceCard === window)
            // Layout changes glide into place; a dragged card follows the pointer directly.
            Behavior on x { enabled: root.settled && window.positioned && !window.dragging && !window.relocating; animation: root.moveAnimation.createObject(window) }
            Behavior on y { enabled: root.settled && window.positioned && !window.dragging && !window.relocating; animation: root.moveAnimation.createObject(window) }
            Behavior on width { enabled: root.settled && window.positioned && !window.relocating; animation: root.moveAnimation.createObject(window) }
            Behavior on height { enabled: root.settled && window.positioned && !window.relocating; animation: root.moveAnimation.createObject(window) }
            NumberAnimation {
                id: appear
                target: window
                property: "shown"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutCubic
            }
            // Newly opened windows fade in; moving an existing window keeps its card.
            Component.onCompleted: {
                updateCapture();
                if (root.settled && !receivingExternal) shown = 0;
                armLayoutAnimation();
            }
            onWindowDataChanged: armLayoutAnimation()
            // The identity model can create this delegate before
            // its metadata map is ready. Keep first placement
            // unanimated until real coordinates have been applied.
            function armLayoutAnimation() {
                if (positioned || !windowData) return;
                Qt.callLater(() => {
                    if (positioned || !windowData) return;
                    positioned = true;
                    if (root.settled && shown === 0) appear.start();
                });
            }
            Connections { target: GlobalStates; function onOverviewOpenChanged() { window.updateCapture(); } }
            // Hyprland only copies windows that overlap their monitor. A pending request for a
            // column off screen never completes and blocks direct scanout, so a closed overview
            // drops those contexts and shows the last snapshot instead. Opening recreates any
            // context without a frame, including one stopped by a failed capture.
            function updateCapture() {
                if (!GlobalStates.overviewOpen) {
                    capturing = (windowData?.viewFraction ?? 0) > 0;
                    if (dragging || dropping) returnHome();
                    return;
                }
                if (!captured) capturing = false;
                capturing = true;
            }
            property point grabPoint: Qt.point(0.5, 0.5)
            function beginDrag(pointer) {
                const point = window.mapToItem(dragLayer, 0, 0);
                lastWindowData = windowData;
                dragging = true;
                cancelPlacement();
                dropping = false;
                snapping = false;
                atHome = false;
                dragX = point.x;
                dragY = point.y;
                if (root.dragController) root.dragController.begin(root, window, pointer, grabPoint);
                else {
                    root.draggedAddress = modelData;
                    root.draggedWindowData = lastWindowData;
                    root.pointerDragging = true;
                }
            }
            // Leave the drag layer at the current spot, then glide back into the lane.
            function cancelPlacement() {
                placementTimeout.stop();
                snapCompletion.stop();
                const requestId = insertionRequestId;
                insertionRequestId = 0;
                if (requestId) ScrollingLayout.cancelInsertion(requestId);
            }
            function returnHome() {
                cancelPlacement();
                const controller = root.dragController;
                const crossScreen = controller?.sourceView === root && controller.targetView !== root;
                if (crossScreen && placementConfirmed) { controller.finish(); return; }
                const home = tape?.cards;
                if (!home && HyprlandData.windowByAddress[modelData]) {
                    root.endDrag();
                    Qt.callLater(window.returnHome);
                    return;
                }
                const point = home ? window.mapToItem(home, 0, 0) : Qt.point(window.x, window.y);
                // Reparent without changing the on-screen position, even halfway
                // through the optimistic snap. Then reconcile with final native geometry.
                relocating = true;
                snapping = false;
                dragX = point.x;
                dragY = point.y;
                dropping = false;
                dragging = false;
                if (crossScreen && GlobalStates.overviewOpen) controller.returnCard();
                else if (root.draggedAddress === modelData) root.endDrag();
                relocating = false;
                atHome = true;
            }
            Connections {
                target: ScrollingLayout
                function onWindowInsertionFinished(requestId, address, success) {
                    if (!window.dropping || requestId !== window.insertionRequestId || address !== window.modelData) return;
                    if (!success) { window.returnHome(); return; }
                    window.placementConfirmed = true;
                    if (window.snapFinished) window.returnHome();
                }
            }
            Timer {
                id: snapCompletion
                interval: Appearance.animation.elementMoveFast.duration
                onTriggered: {
                    window.snapFinished = true;
                    if (window.placementConfirmed) window.returnHome();
                }
            }
            // Recover the card if a placement never completes.
            Timer { id: placementTimeout; interval: 6000; onTriggered: window.returnHome() }
            MouseArea {
                id: windowArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                preventStealing: true
                drag.target: root.pendingDrop ? null : window
                onEntered: window.hovered = true
                onExited: window.hovered = false
                onPressed: mouse => {
                    window.pressed = true;
                    window.didDrag = false;
                    window.grabPoint = Qt.point(mouse.x / window.width, mouse.y / window.height);
                    root.endDrag();
                }
                onPositionChanged: mouse => {
                    if (!drag.active) return;
                    if (!window.dragging) window.beginDrag(windowArea.mapToGlobal(mouse.x, mouse.y));
                    window.didDrag = true;
                    root.updateDrag(windowArea.mapToItem(lanes, mouse.x, mouse.y));
                }
                onReleased: mouse => {
                    window.pressed = false;
                    // A release can arrive at a new position without
                    // a preceding move event; commit that position.
                    if (window.dragging) root.updateDrag(windowArea.mapToItem(lanes, mouse.x, mouse.y));
                    const destination = root.dragController ? root.dragController.targetView : root;
                    const target = destination?.dropTarget;
                    const address = window.modelData;
                    if (!window.dragging) return;
                    if (target) {
                        const placement = Object.assign({}, target, { monitor: destination.monitorName });
                        if (destination !== root) {
                            const point = destination.incomingCard.mapToGlobal(0, 0);
                            const local = dragLayer.mapFromGlobal(point.x, point.y);
                            window.relocating = true;
                            window.dragX = local.x;
                            window.dragY = local.y;
                            window.lastWindowData = destination.draggedWindowData;
                        }
                        if (root.dragController) root.dragController.commit(placement);
                        else root.commitDrop(placement);
                        window.dropping = true;
                        window.placementConfirmed = false;
                        window.snapFinished = false;
                        // Enable animation first, then switch to the reserved slot.
                        // The native transaction completes independently of this motion.
                        window.dragging = false;
                        window.relocating = false;
                        window.snapping = true;
                        snapCompletion.restart();
                        placementTimeout.restart();
                        window.insertionRequestId = ScrollingLayout.insertWindow(destination.monitorName, target.workspace, address, target.anchor, target.before);
                        if (!window.insertionRequestId) window.returnHome();
                    } else window.returnHome();
                }
                onCanceled: {
                    window.pressed = false;
                    if (window.dropping) return;
                    if (window.dragging) window.returnHome(); else root.endDrag();
                }
                onClicked: mouse => {
                    if (window.didDrag) return;
                    if (mouse.button === Qt.MiddleButton)
                        Hyprland.dispatch(`hl.dsp.window.close({ window = ${ScrollingLayout.luaString("address:" + window.modelData)} })`);
                    else { GlobalStates.overviewOpen = false; ScrollingLayout.focusWindow(root.monitorName, window.modelData); }
                }
                onWheel: event => root.wheel(event, tape)
            }
        }
    }
    Item { id: dragLayer; anchors.fill: parent; z: 1000 }
    OverviewWindow {
        id: externalCard
        parent: dragLayer
        readonly property var controller: root.dragController
        readonly property var held: controller?.sourceCard
        readonly property bool followingMotion: held?.dropping || controller?.returning
        // Read x/y explicitly: mapToGlobal() alone does not invalidate its
        // binding as the source card's NumberAnimations advance.
        readonly property var globalPoint: followingMotion && held?.parent
            ? root.toGlobal(held.parent, held.x, held.y) : controller?.pointer
        readonly property var point: globalPoint ? root.fromGlobal(dragLayer, globalPoint) : Qt.point(0, 0)
        windowData: controller?.active && controller.sourceView !== root
            ? root.draggedWindowData ?? controller.dataFor(root) : null
        toplevel: held?.toplevel ?? null
        fallbackSnapshot: held?.snapshot ?? null
        cornerRadius: root.windowRadius
        width: followingMotion ? held?.width ?? 1 : (windowData?.layoutWidth ?? 1) * root.previewScale
        height: followingMotion ? held?.height ?? 1 : (windowData?.layoutHeight ?? 1) * root.previewScale
        x: point.x - (followingMotion ? 0 : width * (controller?.hotSpot.x ?? 0.5))
        y: point.y - (followingMotion ? 0 : height * (controller?.hotSpot.y ?? 0.5))
        visible: (controller?.active ?? false) && controller.sourceView !== root
            && (followingMotion || controller.targetView === root)
        capturing: visible
        liveCapture: visible
        z: 1000
    }
    Timer { id: selectionRestore; interval: 220; onTriggered: root.selectWorkspace(root.activeId) }
    // Dragging near the top or bottom edge scrolls to workspaces outside the three visible lanes,
    // once per rendered frame and faster the closer the pointer is to the edge.
    FrameAnimation {
        id: dragScroll
        property real speed: 0 // px per second
        property real horizontalSpeed: 0
        // Cards can keep moving under a still pointer after a layout change.
        running: root.pointerDragging
        onTriggered: {
            if (root.dragController?.targetView === root)
                root.dragPoint = root.dragPointFromGlobal(root.dragController.pointer);
            const limit = Math.max(0, lanes.contentHeight - lanes.height);
            const next = Math.max(0, Math.min(limit, lanes.contentY + speed * frameTime));
            lanes.contentY = next;
            const tape = root.dragTape;
            if (tape) tape.contentX = Math.max(0, Math.min(tape.contentWidth - tape.width, tape.contentX + horizontalSpeed * frameTime));
            root.updateDrop();
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
