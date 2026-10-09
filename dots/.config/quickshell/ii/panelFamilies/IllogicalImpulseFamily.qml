import QtQuick
import Quickshell

import qs.modules.common
// Keep these imports for Quickshell's virtual module registration. URL loaders
// below still avoid eagerly compiling each panel's component tree.
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.cheatsheet
import qs.modules.ii.dock
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.screenCorners
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebarRight
import qs.modules.ii.overlay
import qs.modules.ii.verticalBar
import qs.modules.ii.wallpaperSelector

Scope {
    component StartupPanel: Loader {
        required property string fileName
        property bool extraCondition: true
        active: Config.ready && extraCondition
        source: Qt.resolvedUrl("../modules/ii/" + fileName)
        // URL loading also moves QML compilation off the GUI thread for async panels.
        // Keep desktop surfaces and essential handlers synchronous; they provide the
        // windows needed for asynchronous incubation to make progress.
        asynchronous: false
    }

    StartupPanel { fileName: "background/Background.qml" }
    StartupPanel { extraCondition: !Config.layout.bar.vertical; fileName: "bar/Bar.qml" }
    StartupPanel { extraCondition: Config.layout.bar.vertical; fileName: "verticalBar/VerticalBar.qml" }
    StartupPanel { fileName: "notificationPopup/NotificationPopup.qml" }
    StartupPanel { fileName: "onScreenDisplay/OnScreenDisplay.qml" }
    StartupPanel { fileName: "overview/Overview.qml" }
    StartupPanel { fileName: "polkit/Polkit.qml" }
    StartupPanel { fileName: "screenCorners/ScreenCorners.qml" }

    StartupPanel { asynchronous: true; fileName: "cheatsheet/Cheatsheet.qml" }
    StartupPanel { asynchronous: true; extraCondition: Config.options.dock.enable; fileName: "dock/Dock.qml" }
    StartupPanel { asynchronous: true; fileName: "mediaControls/MediaControls.qml" }
    StartupPanel { asynchronous: true; fileName: "onScreenKeyboard/OnScreenKeyboard.qml" }
    StartupPanel { asynchronous: true; fileName: "overlay/Overlay.qml" }
    StartupPanel { asynchronous: true; fileName: "regionSelector/RegionSelector.qml" }
    StartupPanel { asynchronous: true; fileName: "screenTranslator/ScreenTranslator.qml" }
    StartupPanel { asynchronous: true; fileName: "sessionScreen/SessionScreen.qml" }
    StartupPanel { asynchronous: true; fileName: "sidebarLeft/SidebarLeft.qml" }
    StartupPanel { asynchronous: true; fileName: "sidebarRight/SidebarRight.qml" }
    StartupPanel { asynchronous: true; fileName: "wallpaperSelector/WallpaperSelector.qml" }
}
