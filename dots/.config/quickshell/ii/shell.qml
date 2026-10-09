//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "modules/common/panels/lock"
import "services"
import "panelFamilies"
import qs.modules.ii.lock
import qs.modules.waffle.lock

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // This must be available before settings and desktop panels finish loading.
    DesktopLock { reloadableId: "desktopLock" }

    // Stuff for every panel family
    ReloadPopup {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
    }

    // Directory scans and update checks must not compete with the first desktop frame.
    Timer {
        id: deferredStartup
        interval: 1000
        onTriggered: {
            Cliphist.refresh()
            Wallpapers.load()
            Updates.load()
        }
    }

    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: Loader {
        required property string identifier
        required property string fileName
        active: Config.ready && Config.options.panelFamily === identifier
        // An inline Component still compiles its entire import tree while inactive.
        // Load only the selected family from its URL, including on family changes.
        source: Qt.resolvedUrl("panelFamilies/" + fileName)
        onLoaded: deferredStartup.restart()
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        fileName: "IllogicalImpulseFamily.qml"
    }

    PanelFamilyLoader {
        identifier: "waffle"
        fileName: "WaffleFamily.qml"
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}
