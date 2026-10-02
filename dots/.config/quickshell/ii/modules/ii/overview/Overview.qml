import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false
    property var savedFullscreen: null
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    Component.onDestruction: restoreFullscreen()

    function prepareSurface() {
        if (savedFullscreen) return;
        const name = Hyprland.focusedMonitor?.name;
        const window = ScrollingLayout.focusedWindow(name, ScrollingLayout.activeId(name));
        if (window?.fullscreen !== 2) return;
        savedFullscreen = { address: window.address, internal: window.fullscreen, client: window.fullscreenClient };
        Hyprland.dispatch("hl.dsp.window.fullscreen_state({ internal = 0, client = " + window.fullscreenClient + ", action = \"set\", window = " + ScrollingLayout.luaString("address:" + window.address) + " })");
    }
    function restoreFullscreen() {
        const saved = savedFullscreen;
        savedFullscreen = null;
        if (!saved || !HyprlandData.windowByAddress[saved.address]) return;
        Hyprland.dispatch("hl.dsp.window.fullscreen_state({ internal = " + saved.internal + ", client = " + saved.client + ", action = \"set\", window = " + ScrollingLayout.luaString("address:" + saved.address) + " })");
    }
    function focusSearch() {
        if (!GlobalStates.overviewOpen) return;
        Qt.callLater(() => searchWidget.focusSearchInput());
        inputMethodRestoreTimer.begin();
    }

    Process { id: inputMethodActivate; command: ["fcitx5-remote", "-o"] }
    Timer {
        id: inputMethodRestoreTimer
        property int attempts: 0
        interval: 20
        repeat: true
        function begin() { attempts = 0; restart(); }
        onTriggered: {
            if (!GlobalStates.overviewOpen) { stop(); return; }
            searchWidget.focusSearchInput();
            attempts++;
            if ((attempts >= 15 && searchWidget.Window.active && GlobalFocusGrab.hasActive(searchWidget)) || attempts >= 150) {
                stop();
                inputMethodActivationDelay.restart();
            }
        }
    }
    Timer {
        id: inputMethodActivationDelay
        interval: 20
        onTriggered: { if (GlobalStates.overviewOpen) inputMethodActivate.running = true; }
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen) {
                searchWidget.disableExpandAnimation();
                overviewScope.dontAutoCancelSearch = false;
                inputMethodRestoreTimer.stop();
                inputMethodActivationDelay.stop();
                overviewScope.restoreFullscreen();
            } else {
                if (!overviewScope.dontAutoCancelSearch) searchWidget.cancelSearch();
                overviewScope.prepareSurface();
                overviewScope.focusSearch();
            }
        }
    }

    // Overview and search share one keyboard-focused surface, including the input method.
    PanelWindow {
        id: panelWindow
        screen: overviewScope.focusedScreen
        property string searchingText: ""
        visible: GlobalStates.overviewOpen
        color: "transparent"
        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        onScreenChanged: { if (visible) Qt.callLater(overviewScope.focusSearch); }

        MouseArea {
            anchors.fill: parent
            onPressed: GlobalStates.overviewOpen = false
        }
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
            spacing: -8
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                    event.accepted = true;
                }
            }
            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                overviewNavigation: overviewLoader.visible ? overviewLoader.item : null
                Synchronizer on searchingText { property alias source: panelWindow.searchingText }
            }
            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                visible: panelWindow.searchingText === ""
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    onSearchRequested: text => overviewScope.openSearch(text)
                }
            }
        }
        function setSearchingText(text) { searchWidget.setSearchingText(text); searchWidget.focusFirstItem(); }
    }

    function openSearch(text) {
        dontAutoCancelSearch = true;
        panelWindow.setSearchingText(text);
        GlobalStates.overviewOpen = true;
        focusSearch();
    }
    function toggleOverview() { GlobalStates.overviewOpen = !GlobalStates.overviewOpen; }
    function toggleClipboard() {
        const prefix = Config.options.search.prefix.clipboard;
        if (GlobalStates.overviewOpen && panelWindow.searchingText.startsWith(prefix)) GlobalStates.overviewOpen = false;
        else openSearch(prefix);
    }
    function toggleEmojis() {
        const prefix = Config.options.search.prefix.emojis;
        if (GlobalStates.overviewOpen && panelWindow.searchingText.startsWith(prefix)) GlobalStates.overviewOpen = false;
        else openSearch(prefix);
    }
    IpcHandler {
        target: "search"
        function toggle() { overviewScope.toggleOverview(); }
        function workspacesToggle() { overviewScope.toggleOverview(); }
        function close() { GlobalStates.overviewOpen = false; }
        function open() { overviewScope.openSearch(""); }
        function toggleReleaseInterrupt() { GlobalStates.superReleaseMightTrigger = false; }
        function clipboardToggle() { overviewScope.toggleClipboard(); }
        function overview(): void { overviewScope.toggleOverview(); }
        function geometry(): string { return JSON.stringify(overviewLoader.item?.geometry() ?? []); }
        function state(): string {
            return JSON.stringify({ open: GlobalStates.overviewOpen, search: panelWindow.searchingText !== "",
                overview: GlobalStates.overviewOpen && overviewLoader.visible && overviewLoader.active,
                monitor: overviewScope.focusedScreen?.name, focused: GlobalFocusGrab.hasActive(searchWidget),
                searchFocused: GlobalFocusGrab.hasActive(searchWidget), dropWorkspace: overviewLoader.item?.dropWorkspace ?? -1,
                selection: overviewLoader.item?.selectedAddress ?? "", workspace: overviewLoader.item?.selectedWorkspace ?? 0,
                query: panelWindow.searchingText });
        }
    }
    GlobalShortcut { name: "searchToggle"; description: "Toggles overview and search"; onPressed: overviewScope.toggleOverview() }
    GlobalShortcut { name: "overviewWorkspacesClose"; description: "Closes overview"; onPressed: GlobalStates.overviewOpen = false }
    GlobalShortcut { name: "overviewWorkspacesToggle"; description: "Toggles overview and search"; onPressed: overviewScope.toggleOverview() }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles overview and search on release"
        onPressed: GlobalStates.superReleaseMightTrigger = true
        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) { GlobalStates.superReleaseMightTrigger = true; return; }
            overviewScope.toggleOverview();
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Suppress the bare Win action when another shortcut is used"
        onPressed: GlobalStates.superReleaseMightTrigger = false
    }
    GlobalShortcut { name: "overviewClipboardToggle"; description: "Toggle clipboard search"; onPressed: overviewScope.toggleClipboard() }
    GlobalShortcut { name: "overviewEmojiToggle"; description: "Toggle emoji search"; onPressed: overviewScope.toggleEmojis() }
}
