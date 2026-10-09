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
    property var fallbackSnapshot: null
    property bool snapshotPending: false
    property int captureGeneration: 0
    property string snapshotAddress: ""
    // A new card on another output inherits the held frame before its own
    // capture is ready. Keep ownership when the drag controller is cleared.
    onFallbackSnapshotChanged: { if (fallbackSnapshot) snapshot = fallbackSnapshot; }
    onWindowDataChanged: {
        const address = windowData?.address ?? "";
        if (address && address !== snapshotAddress) {
            snapshotAddress = address;
            captureGeneration++;
            snapshot = fallbackSnapshot;
        }
    }
    property real cornerRadius: Appearance.rounding.small
    readonly property bool centerIcons: Config.layoutFor("scrolling").overview.centerIcons
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
        retainWhileLoading: true
    }
    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: root.capturing ? root.toplevel : null
        live: GlobalStates.overviewOpen && (root.liveCapture || !hasContent)
        constraintSize: Qt.size(root.width, root.height)
        onCaptureSourceChanged: root.captureGeneration++
        onHasContentChanged: {
            root.captureGeneration++;
        }
        onStopped: captureRetry.restart()
        // Overlays are siblings, so the snapshot holds only the window contents.
        Timer {
            interval: 1000
            repeat: true
            triggeredOnStart: false
            running: GlobalStates.overviewOpen && root.liveCapture && view.hasContent
                && root.width > 1 && root.height > 1 && (view.Window.window?.visible ?? false)
            onTriggered: root.saveSnapshot()
        }
    }
    function saveSnapshot() {
        if (snapshotPending || !view.hasContent || width <= 1 || height <= 1
            || !(view.Window.window?.visible ?? false)) return;
        const generation = captureGeneration;
        const source = view.captureSource;
        const output = view.Window.window;
        snapshotPending = true;
        const started = view.grabToImage(result => {
            snapshotPending = false;
            // Reparenting, a failed screencopy or a source change can clear the
            // texture between scheduling this grab and rendering it.
            if (view.hasContent && generation === captureGeneration && source === view.captureSource
                && output === view.Window.window && (output?.visible ?? false) && result?.url)
                root.snapshot = result;
        });
        if (!started) snapshotPending = false;
    }
    Timer {
        id: firstSnapshot
        interval: 32
        repeat: true
        running: GlobalStates.overviewOpen && !root.snapshot && view.hasContent
            && root.width > 1 && root.height > 1 && (view.Window.window?.visible ?? false)
        onTriggered: root.saveSnapshot()
    }
    Timer {
        id: captureRetry
        interval: 250
        onTriggered: {
            if (!GlobalStates.overviewOpen || !root.capturing || !root.liveCapture
                || (root.windowData?.viewFraction ?? 0) <= 0 || view.hasContent) return;
            // A stopped context is not recreated just by setting live=true.
            view.captureSource = null;
            view.captureSource = Qt.binding(() => root.capturing ? root.toplevel : null);
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
