pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets

Item {
    id: root
    readonly property string monitorName: root.QsWindow.window?.screen?.name ?? ""
    readonly property bool monitorFocused: ScrollingLayout.focusedName() === monitorName
    // A visible scratchpad takes over the ribbon, as it takes keyboard focus.
    readonly property int specialId: HyprlandData.monitors.find(m => m.name === monitorName)?.specialWorkspace?.id ?? 0
    readonly property int workspaceId: specialId !== 0 ? specialId : ScrollingLayout.activeId(monitorName)
    readonly property var workspaceOrder: ScrollingLayout.workspaceIds(monitorName)
    property var renderedWorkspaces: []
    property int displayedWorkspace: 0
    property bool initialized: false
    readonly property real iconButtonWidth: 26
    readonly property real iconSpacing: 2
    readonly property real activeIconMargin: 2
    readonly property real activeIconSize: iconButtonWidth - activeIconMargin * 2

    implicitWidth: 260
    implicitHeight: Appearance.sizes.baseBarHeight - 10

    function canonicalOrder() {
        const order = workspaceOrder.slice();
        if (workspaceId < 0 && !order.includes(workspaceId)) {
            // Scratch overlays the current workspace, so its ribbon enters
            // from the adjacent row rather than traversing all workspaces.
            const underlyingIndex = order.indexOf(ScrollingLayout.activeId(monitorName));
            order.splice(underlyingIndex < 0 ? order.length : underlyingIndex + 1, 0, workspaceId);
        } else if (workspaceId !== 0 && !order.includes(workspaceId)) {
            order.push(workspaceId);
        }
        return order;
    }

    function settleWorkspaces() {
        // Keep outgoing empty workspaces until they have scrolled out. Dynamic
        // workspace pruning must not destroy a row halfway through its exit.
        if (!initialized || workspaceSlide.running) return;
        if (workspaceId !== displayedWorkspace) { switchWorkspace(); return; }
        renderedWorkspaces = canonicalOrder();
        workspaceTape.y = -Math.max(0, renderedWorkspaces.indexOf(workspaceId)) * viewport.height;
    }

    function switchWorkspace() {
        if (!initialized) return;
        if (workspaceId === displayedWorkspace) { settleWorkspaces(); return; }
        workspaceSlide.stop();
        const previous = displayedWorkspace;
        if (!renderedWorkspaces.includes(workspaceId)) {
            const oldIndex = Math.max(0, renderedWorkspaces.indexOf(previous));
            const offset = workspaceTape.y + oldIndex * viewport.height;
            const order = renderedWorkspaces.slice();
            const canonical = canonicalOrder();
            // A newly inserted workspace can precede the current one; numeric
            // IDs do not describe the vertical order.
            const after = canonical.slice(canonical.indexOf(workspaceId) + 1).find(id => order.includes(id));
            order.splice(after === undefined ? order.length : order.indexOf(after), 0, workspaceId);
            renderedWorkspaces = order;
            workspaceTape.y = -Math.max(0, order.indexOf(previous)) * viewport.height + offset;
        }
        displayedWorkspace = workspaceId;
        const target = -Math.max(0, renderedWorkspaces.indexOf(workspaceId)) * viewport.height;
        if (previous === 0 || workspaceId === 0 || target === workspaceTape.y) {
            workspaceTape.y = target;
            settleWorkspaces();
        } else {
            workspaceSlide.to = target;
            workspaceSlide.start();
        }
    }

    onWorkspaceIdChanged: Qt.callLater(switchWorkspace)
    onWorkspaceOrderChanged: Qt.callLater(settleWorkspaces)
    onMonitorNameChanged: {
        workspaceSlide.stop();
        displayedWorkspace = workspaceId;
        Qt.callLater(settleWorkspaces);
    }
    Component.onCompleted: {
        initialized = true;
        displayedWorkspace = workspaceId;
        settleWorkspaces();
    }

    function focusWindow(address) {
        if (GlobalStates.screenLocked) return;
        // Hyprland also warps on native activation. Suppress it only inside this
        // synchronous dispatch, then restore the user's setting even on failure.
        Hyprland.dispatch(`function()
            local previous = hl.get_config("cursor:no_warps")
            hl.config({ cursor = { no_warps = true } })
            local ok, result = pcall(function()
                return hl.dispatch(hl.dsp.focus({ window = ${ScrollingLayout.luaString("address:" + address)} }))
            end)
            hl.config({ cursor = { no_warps = previous } })
            if not ok then error(result) end
            return result
        end`);
    }

    function toggleOverview() {
        // An overview opened from another output belongs to that output.
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${ScrollingLayout.luaString(monitorName)} })`);
        GlobalStates.overviewMonitorRequest = GlobalStates.overviewOpen ? "" : monitorName;
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    component RibbonButton: RippleButton {
        implicitWidth: 24
        implicitHeight: root.implicitHeight
        padding: 0
        Layout.alignment: Qt.AlignVCenter
        buttonRadius: root.activeIconSize / 2
        // Backgrounds live in shared layers so focus can stretch between icons.
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colBackgroundToggled: "transparent"
        colBackgroundToggledHover: "transparent"
        altAction: () => root.toggleOverview()
    }

    // The original workspace indicator moves its leading end in 100 ms and
    // trailing end in 300 ms. Reuse the same model rather than a per-button fill.
    component RibbonIndicator: Item {
        id: indicator
        required property int index
        property alias color: pill.color
        readonly property alias indicatorRectangle: pill
        anchors.fill: parent
        visible: index >= 0
        AnimatedTabIndexPair {
            id: pair
            index: Math.max(0, indicator.index)
        }
        StyledRectangle {
            id: pill
            anchors.verticalCenter: parent.verticalCenter
            contentLayer: StyledRectangle.ContentLayer.Group
            x: Math.min(pair.idx1, pair.idx2) * (root.iconButtonWidth + root.iconSpacing) + root.activeIconMargin
            width: Math.abs(pair.idx1 - pair.idx2) * (root.iconButtonWidth + root.iconSpacing) + root.activeIconSize
            height: Math.min(root.activeIconSize, parent.height)
            radius: height / 2
            color: Appearance.colors.colPrimary
        }
    }

    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        onHeightChanged: Qt.callLater(root.settleWorkspaces)

        Item {
            id: workspaceTape
            width: parent.width
            height: root.renderedWorkspaces.length * viewport.height

            Repeater {
                model: ScriptModel { values: root.renderedWorkspaces }
                delegate: Item {
                    id: workspaceRow
                    required property int modelData
                    readonly property var windows: ScrollingLayout.windowsForWorkspace(root.monitorName, modelData)
                    readonly property var windowByAddress: windows.reduce((result, window) => {
                        result[window.address] = window;
                        return result;
                    }, {})
                    readonly property var focusedWindow: ScrollingLayout.focusedWindow(root.monitorName, modelData)
                    readonly property int focusedIndex: windows.findIndex(w => w.address === focusedWindow?.address)
                    property string hoveredAddress: ""
                    readonly property int hoveredIndex: windows.findIndex(w => w.address === hoveredAddress)
                    width: viewport.width
                    height: viewport.height
                    y: Math.max(0, root.renderedWorkspaces.indexOf(modelData)) * height
                    // Only the active workspace receives clicks, even while its
                    // outgoing neighbour is still partly visible.
                    enabled: modelData === root.workspaceId

                    Item {
                        id: iconStrip
                        anchors.verticalCenter: parent.verticalCenter
                        width: iconTape.width
                        height: parent.height
                        readonly property real focusCenteredX: (parent.width - root.iconButtonWidth) / 2
                            - Math.max(0, workspaceRow.focusedIndex) * (root.iconButtonWidth + root.iconSpacing)
                        x: width <= parent.width ? (parent.width - width) / 2
                            : Math.max(parent.width - width, Math.min(0, focusCenteredX))
                        Behavior on x {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        // Like occupiedIndicators in Workspaces.qml: every
                        // window occupies a slot, joined into one muted capsule.
                        Pill {
                            // Keep rounded ends when the icon tape overflows the viewport.
                            parent: workspaceRow
                            z: -1
                            anchors.verticalCenter: parent.verticalCenter
                            x: (parent.width - width) / 2
                            width: Math.min(iconStrip.width, workspaceRow.width)
                            height: Math.min(root.iconButtonWidth, parent.height)
                            visible: workspaceRow.windows.length > 0
                            color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.4)
                            // Center directly from the animated width. Animating
                            // x again would chase that width and lag behind the icons.
                            Behavior on width {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }
                        RibbonIndicator {
                            id: activeIndicator
                            z: 1
                            index: workspaceRow.focusedIndex
                            color: root.monitorFocused ? Appearance.colors.colPrimary
                                : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }
                        RibbonIndicator {
                            id: interactionIndicator
                            z: 2
                            index: workspaceRow.hoveredIndex >= 0 ? workspaceRow.hoveredIndex : workspaceRow.focusedIndex
                            color: "transparent"
                            StateOverlay {
                                anchors.fill: interactionIndicator.indicatorRectangle
                                radius: root.activeIconSize / 2
                                hover: workspaceRow.hoveredIndex >= 0
                                press: windowRepeater.itemAt(workspaceRow.hoveredIndex)?.down ?? false
                                drag: true
                                contentColor: Appearance.colors.colPrimary
                            }
                        }
                        Row {
                            id: iconTape
                            z: 3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.iconSpacing
                            // Keep the existing icon objects gliding into their new slots.
                            move: Transition {
                                NumberAnimation {
                                    properties: "x"
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                            Repeater {
                                id: windowRepeater
                                // Keep only immutable identities in the ordering model.
                                // With rich objects, ScriptModel's batched dataChanged path
                                // can replace later identities instead of emitting moves
                                // when metadata and order change in the same snapshot.
                                model: ScriptModel { values: workspaceRow.windows.map(window => window.address) }
                                delegate: RibbonButton {
                                    id: windowButton
                                    required property string modelData
                                    readonly property var windowData: workspaceRow.windowByAddress[modelData] ?? null
                                    implicitWidth: root.iconButtonWidth
                                    toggled: modelData === workspaceRow.focusedWindow?.address
                                    opacity: toggled ? 1 : (windowData?.viewFraction ?? 0) > 0.05 ? 0.9 : 0.45
                                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                                    onHoveredChanged: {
                                        if (hovered) workspaceRow.hoveredAddress = modelData;
                                        else if (workspaceRow.hoveredAddress === modelData) workspaceRow.hoveredAddress = "";
                                    }
                                    onClicked: root.focusWindow(modelData)
                                    contentItem: Item {
                                        StyledImage {
                                            anchors.centerIn: parent
                                            width: 19
                                            height: 19
                                            scale: windowButton.toggled ? 1 : 0.8
                                            Behavior on scale { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                                            fillMode: Image.PreserveAspectFit
                                            // Tiny theme icons load synchronously, including during hot reload.
                                            asynchronous: false
                                            retainWhileLoading: false
                                            cache: false
                                            mipmap: false
                                            source: Quickshell.iconPath(AppSearch.guessIcon(windowButton.windowData?.class ?? ""), "image-missing")
                                        }
                                        Rectangle {
                                            visible: windowButton.windowData?.floating ?? false
                                            anchors { bottom: parent.bottom; right: parent.right }
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: workspaceSlide
        target: workspaceTape
        property: "y"
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        onFinished: root.settleWorkspaces()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.toggleOverview()
        // Touchpads send many small deltas; move one column per mouse-wheel notch.
        property real wheelDelta: 0
        onWheel: event => {
            const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
            const threshold = Math.max(1, Config.options.interactions.scrolling.mouseScrollDeltaThreshold);
            if (delta * wheelDelta < 0) wheelDelta = 0;
            wheelDelta += delta;
            while (Math.abs(wheelDelta) >= threshold) {
                ScrollingLayout.focusColumn(root.monitorName, wheelDelta > 0 ? -1 : 1, root.workspaceId);
                wheelDelta -= Math.sign(wheelDelta) * threshold;
            }
            event.accepted = true;
        }
    }
}
