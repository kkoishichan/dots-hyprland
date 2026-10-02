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
    readonly property real workspaceRadius: windowRadius + windowMargin
    readonly property real framePadding: 10
    readonly property real verticalPadding: (Appearance.sizes.elevationMargin + framePadding) * 2
    readonly property int visibleLaneCount: Math.min(3, workspaceIds.length)
    readonly property real availableHeight: Math.max(1, (root.QsWindow.window?.height ?? viewport.height) - 120)
    readonly property real previewHeight: Math.max(1, Math.floor(Math.min(260, viewport.height * Config.options.overview.scale,
        (availableHeight - verticalPadding - laneGap * 2) / 3 - windowMargin * 2)))
    readonly property real previewScale: previewHeight / viewport.height
    readonly property real laneHeight: previewHeight + windowMargin * 2
    property int selectedWorkspace: activeId
    property string selectedAddress: ""
    property int dropWorkspace: -1
    signal searchRequested(string text)

    implicitWidth: Math.min(1100, viewport.width - 100)
    implicitHeight: verticalPadding + visibleLaneCount * laneHeight + Math.max(0, visibleLaneCount - 1) * laneGap

    function selectWorkspace(id) {
        selectedWorkspace = id;
        selectedAddress = ScrollingLayout.focusedWindow(monitorName, id)?.address ?? "";
        const index = workspaceIds.indexOf(id);
        const top = index * (laneHeight + laneGap);
        if (top < lanes.contentY) lanes.contentY = top;
        else if (top + laneHeight > lanes.contentY + lanes.height) lanes.contentY = top + laneHeight - lanes.height;
        lanes.contentY = Math.max(0, Math.min(lanes.contentHeight - lanes.height, lanes.contentY));
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
        const windows = ScrollingLayout.windowsForWorkspace(monitorName, selectedWorkspace);
        if (!windows.length) return;
        const index = windows.findIndex(w => w.address === selectedAddress);
        selectedAddress = windows[Math.max(0, Math.min(windows.length - 1, index + delta))].address;
    }
    function wheel(event, tape) {
        if (event.angleDelta.x || (event.modifiers & Qt.ShiftModifier)) {
            const delta = event.angleDelta.x || event.angleDelta.y;
            tape.contentX = Math.max(0, Math.min(tape.contentWidth - tape.width, tape.contentX - delta));
        } else lanes.contentY = Math.max(0, Math.min(lanes.contentHeight - lanes.height, lanes.contentY - event.angleDelta.y));
        event.accepted = true;
    }
    onWorkspaceIdsChanged: {
        if (!workspaceIds.includes(selectedWorkspace)) selectWorkspace(activeId);
    }
    Component.onCompleted: Qt.callLater(() => selectWorkspace(activeId))
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
        else if (event.key === Qt.Key_Left) changeWindow(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) changeWindow(event.modifiers & Qt.ShiftModifier ? -1 : 1);
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
                        readonly property real tapeWidth: (extent.right - extent.left) * root.previewScale + 16
                        readonly property bool selected: root.selectedWorkspace === workspaceId
                        readonly property bool receivingDrop: root.dropWorkspace === workspaceId
                        width: laneColumn.width
                        height: root.laneHeight
                        radius: root.workspaceRadius
                        color: receivingDrop ? ColorUtils.mix(Appearance.colors.colSurfaceContainerLow, Appearance.colors.colLayer1Hover, 0.1)
                            : Appearance.colors.colSurfaceContainerLow
                        border.width: 2
                        border.color: selected ? Appearance.colors.colSecondary : receivingDrop ? Appearance.colors.colLayer2Hover : "transparent"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { GlobalStates.overviewOpen = false; ScrollingLayout.focusWorkspace(root.monitorName, lane.workspaceId); }
                        }
                        Flickable {
                            id: tape
                            objectName: "workspaceTape"
                            anchors { fill: parent; margins: root.windowMargin }
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
                            readonly property real inset: Math.max(8, (width - lane.tapeWidth) / 2 + 8)
                            function centerViewport() {
                                const center = (-lane.extent.left + root.viewport.width / 2) * root.previewScale + inset;
                                contentX = Math.max(0, Math.min(contentWidth - width, center - width / 2));
                            }
                            function revealSelection() {
                                const selected = lane.windows.find(w => w.address === root.selectedAddress);
                                if (!selected || !lane.selected) return;
                                const left = (selected.localX - lane.extent.left) * root.previewScale + inset;
                                const right = left + selected.layoutWidth * root.previewScale;
                                if (left < contentX) contentX = left - 8;
                                else if (right > contentX + width) contentX = right - width + 8;
                                contentX = Math.max(0, Math.min(contentWidth - width, contentX));
                            }
                            Component.onCompleted: Qt.callLater(centerViewport)
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
                                    windowData: modelData
                                    cornerRadius: root.windowRadius
                                    toplevel: ScrollingLayout.toplevelForAddress(modelData.address)
                                    selected: root.selectedWorkspace === lane.workspaceId && root.selectedAddress === modelData.address
                                    x: initialX
                                    y: initialY
                                    width: modelData.layoutWidth * root.previewScale
                                    height: modelData.layoutHeight * root.previewScale
                                    z: dragging ? 100 : modelData.floating ? 3 : modelData.hidden ? 0 : 1
                                    opacity: modelData.hidden ? 0.45 : 1
                                    Drag.active: dragging
                                    Drag.source: window
                                    Drag.hotSpot.x: width / 2
                                    Drag.hotSpot.y: height / 2
                                    states: State { when: window.dragging; ParentChange { target: window; parent: dragLayer } }
                                    function resetPosition() { x = Qt.binding(() => initialX); y = Qt.binding(() => initialY); }
                                    MouseArea {
                                        id: windowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        drag.target: window
                                        onEntered: window.hovered = true
                                        onExited: window.hovered = false
                                        onPressed: { window.pressed = true; window.didDrag = false; root.dropWorkspace = -1; }
                                        onPositionChanged: { if (drag.active) { window.didDrag = true; window.dragging = true; } }
                                        onReleased: {
                                            window.pressed = false;
                                            if (window.didDrag && root.dropWorkspace > 0 && root.dropWorkspace !== lane.workspaceId)
                                                ScrollingLayout.moveWindowTo(root.monitorName, root.dropWorkspace, window.modelData.address, false);
                                            window.dragging = false;
                                            root.dropWorkspace = -1;
                                            Qt.callLater(window.resetPosition);
                                        }
                                        onCanceled: { window.pressed = false; window.dragging = false; root.dropWorkspace = -1; Qt.callLater(window.resetPosition); }
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
                        DropArea {
                            anchors.fill: parent
                            onEntered: root.dropWorkspace = lane.workspaceId
                            onExited: { if (root.dropWorkspace === lane.workspaceId) root.dropWorkspace = -1; }
                        }
                    }
                }
            }
        }
    }
    Item { id: dragLayer; anchors.fill: parent; z: 1000 }
    Timer { id: selectionRestore; interval: 220; onTriggered: root.selectWorkspace(root.activeId) }
}
