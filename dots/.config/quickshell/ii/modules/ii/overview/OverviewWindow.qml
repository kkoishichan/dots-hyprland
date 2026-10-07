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
    // Whether a capture context exists; the overview drops it for columns off screen when it closes.
    property bool capturing: true
    readonly property alias captured: view.hasContent
    // A thumbnail-sized copy of the last live frame, shown when no live frame is available.
    property var snapshot: null
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
    Image {
        anchors.fill: parent
        visible: !view.hasContent
        source: root.snapshot?.url ?? ""
        cache: false
    }
    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: root.capturing ? root.toplevel : null
        live: GlobalStates.overviewOpen && (root.liveCapture || !hasContent)
        constraintSize: Qt.size(root.width, root.height)
        // Overlays are siblings, so the snapshot holds only the window contents.
        Timer {
            interval: 1000
            repeat: true
            triggeredOnStart: true
            running: GlobalStates.overviewOpen && root.liveCapture && view.hasContent && root.width > 1
            onTriggered: view.grabToImage(result => root.snapshot = result)
        }
    }
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
