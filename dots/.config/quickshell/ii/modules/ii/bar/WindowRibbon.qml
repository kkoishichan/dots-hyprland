pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    readonly property string monitorName: root.QsWindow.window?.screen?.name ?? ""
    readonly property bool monitorFocused: Hyprland.focusedMonitor?.name === monitorName
    // A visible scratchpad takes over the ribbon, as it takes keyboard focus.
    readonly property int specialId: HyprlandData.monitors.find(m => m.name === monitorName)?.specialWorkspace?.id ?? 0
    readonly property int workspaceId: specialId !== 0 ? specialId : ScrollingLayout.activeId(monitorName)
    readonly property var windows: ScrollingLayout.windowsForWorkspace(monitorName, workspaceId)
    readonly property var focusedWindow: ScrollingLayout.focusedWindow(monitorName, workspaceId)
    readonly property int focusedIndex: windows.findIndex(w => w.address === focusedWindow?.address)
    readonly property real iconButtonWidth: 26

    implicitWidth: 260
    implicitHeight: Appearance.sizes.baseBarHeight - 10

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
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    component RibbonButton: RippleButton {
        implicitWidth: 24
        implicitHeight: root.implicitHeight
        padding: 0
        Layout.alignment: Qt.AlignVCenter
        buttonRadius: Appearance.rounding.small
        altAction: () => root.toggleOverview()
    }

    RowLayout {
        anchors.fill: parent

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Row {
                id: iconTape
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                readonly property real focusCenteredX: (parent.width - root.iconButtonWidth) / 2
                    - Math.max(0, root.focusedIndex) * (root.iconButtonWidth + spacing)
                x: width <= parent.width ? (parent.width - width) / 2
                    : Math.max(parent.width - width, Math.min(0, focusCenteredX))
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Repeater {
                    model: ScriptModel { values: root.windows; objectProp: "address" }
                    delegate: RibbonButton {
                        id: windowButton
                        required property var modelData
                        implicitWidth: root.iconButtonWidth
                        toggled: modelData.address === root.focusedWindow?.address
                        // Another output's last focused window is marked more faintly than the keyboard focus.
                        colBackgroundToggled: root.monitorFocused ? Appearance.colors.colSecondaryContainer
                            : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.6)
                        colBackgroundToggledHover: root.monitorFocused ? Appearance.colors.colSecondaryContainerHover
                            : ColorUtils.transparentize(Appearance.colors.colSecondaryContainerHover, 0.4)
                        opacity: toggled ? 1 : modelData.viewFraction > 0.05 ? 0.9 : 0.45
                        onClicked: root.focusWindow(modelData.address)
                        contentItem: Item {
                            StyledImage {
                                anchors.centerIn: parent
                                width: 19
                                height: 19
                                fillMode: Image.PreserveAspectFit
                                // Tiny theme icons load synchronously, including during hot reload.
                                asynchronous: false
                                retainWhileLoading: false
                                cache: false
                                mipmap: false
                                source: Quickshell.iconPath(AppSearch.guessIcon(windowButton.modelData.class), "image-missing")
                            }
                            Rectangle {
                                visible: windowButton.modelData.floating
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
