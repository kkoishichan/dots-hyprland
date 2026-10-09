import QtQuick
import Quickshell
import qs
import qs.modules.common

// Keep the protocol owner outside Config.ready-gated desktop panel loaders.
// Restore its target state before LazyLoader transfers the existing lock.
Scope {
    id: root

    PersistentProperties {
        id: state
        reloadableId: "desktopLockState"
        property bool locked: false
        property string family: "ii"
        onLoaded: GlobalStates.screenLocked = locked
    }

    LazyLoader {
        id: controller
        reloadableId: "desktopLockController"
        active: true
        source: Qt.resolvedUrl(state.family === "waffle"
            ? "../../../waffle/lock/WaffleLock.qml" : "../../../ii/lock/Lock.qml")
    }

    function syncFamily() {
        if (!Config.ready || GlobalStates.screenLocked) return;
        const family = Config.options.panelFamily === "waffle" ? "waffle" : "ii";
        if (family === state.family) return;
        controller.active = false;
        state.family = family;
        controller.active = true;
    }

    Component.onCompleted: Qt.callLater(root.syncFamily)
    Connections {
        target: Config
        function onReadyChanged() { root.syncFamily(); }
    }
    Connections {
        target: Config.options
        function onPanelFamilyChanged() { root.syncFamily(); }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            state.locked = GlobalStates.screenLocked;
            if (!state.locked) Qt.callLater(root.syncFamily);
        }
    }
}
