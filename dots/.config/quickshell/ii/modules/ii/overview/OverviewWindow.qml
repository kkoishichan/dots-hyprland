pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    property var toplevel
    property var windowData
    property bool selected: false
    property bool hovered: false
    property bool pressed: false
    // Offscreen thumbnails keep a single frame instead of capturing every frame.
    property bool liveCapture: true
    property real cornerRadius: Appearance.rounding.small
    readonly property bool centerIcons: Config.options.overview.centerIcons
    readonly property real iconBaseSize: Math.min(width, height)
    readonly property bool compactMode: Appearance.font.pixelSize.smaller * 4 > iconBaseSize

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.cornerRadius
        }
    }
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainerHigh
    }
    ScreencopyView {
        anchors.fill: parent
        captureSource: GlobalStates.overviewOpen ? root.toplevel : null
        // Stay live until the first frame arrives so offscreen thumbnails are never blank.
        live: root.liveCapture || !hasContent
        constraintSize: Qt.size(root.width, root.height)

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: root.pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5)
                : root.hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7)
                : ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.width: root.selected ? 2 : 1
            border.color: root.selected ? Appearance.colors.colSecondary : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
        }
        StyledImage {
            anchors {
                top: root.centerIcons ? undefined : parent.top
                left: root.centerIcons ? undefined : parent.left
                centerIn: root.centerIcons ? parent : undefined
                margins: root.iconBaseSize * 0.06
            }
            width: root.iconBaseSize * (root.compactMode ? 0.6 : root.centerIcons ? 0.35 : 0.15)
            height: width
            fillMode: Image.PreserveAspectFit
            asynchronous: false
            retainWhileLoading: false
            cache: false
            mipmap: false
            source: Quickshell.iconPath(AppSearch.guessIcon(root.windowData?.class), "image-missing")
        }
    }
}
