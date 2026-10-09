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
    // Keep the overview after its first use so each card keeps its last captured frame;
    // columns scrolled off screen cannot be captured again until they return.
    property bool overviewLoaded: false
    property string openedMonitor: ""
    // Keep the opening output throughout a drag; layout placement can briefly
    // focus a window on another output while this surface stays open.
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === openedMonitor)
        ?? Quickshell.screens.find(s => s.name === ScrollingLayout.focusedName()) ?? Quickshell.screens[0]
    Component.onDestruction: restoreFullscreen()
    OverviewDragController { id: overviewDrag }

    function prepareSurface() {
        if (!DesktopLayout.scrolling) return;
        if (savedFullscreen) return;
        const name = focusedScreen?.name;
        const window = ScrollingLayout.focusedWindow(name, ScrollingLayout.activeId(name));
        if (window?.fullscreen !== 2) return;
        savedFullscreen = { address: window.address, internal: window.fullscreen, client: window.fullscreenClient };
        Hyprland.dispatch("hl.dsp.window.fullscreen_state({ internal = 0, client = " + window.fullscreenClient + ", action = \"set\", window = " + ScrollingLayout.luaString("address:" + window.address) + " })");
    }
    function restoreFullscreen() {
        const saved = savedFullscreen;
        savedFullscreen = null;
        const window = saved ? HyprlandData.windowByAddress[saved.address] : null;
        if (!window) return;
        // Selecting another window on the same workspace takes focus under the
        // fullscreen window (misc:on_focus_under_fullscreen); restoring first only flashes.
        const target = HyprlandData.windowByAddress[ScrollingLayout.focusRequest];
        if (target && target.address !== saved.address && target.workspace?.id === window.workspace?.id) return;
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
                // Selections close the overview before focusing; decide after that request.
                Qt.callLater(overviewScope.restoreFullscreen);
            } else {
                overviewScope.openedMonitor = GlobalStates.overviewMonitorRequest || ScrollingLayout.focusedName();
                GlobalStates.overviewMonitorRequest = "";
                overviewScope.overviewLoaded = true;
                ScrollingLayout.focusRequest = "";
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
        WlrLayershell.keyboardFocus: !visible ? WlrKeyboardFocus.None
            : ScrollingLayout.placingWindow ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }
        onScreenChanged: { if (visible) Qt.callLater(overviewScope.focusSearch); }

        MouseArea {
            id: dismissArea
            anchors.fill: parent
            // Only presses outside the search field and overview card dismiss it.
            onPressed: mouse => {
                const inside = [searchWidget, overviewLoader].some(item => item.visible
                    && item.contains(item.mapFromItem(dismissArea, mouse.x, mouse.y)));
                if (!inside) GlobalStates.overviewOpen = false;
            }
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
                overviewNavigation: DesktopLayout.scrolling && overviewLoader.visible ? overviewLoader.item : null
                Synchronizer on searchingText { property alias source: panelWindow.searchingText }
            }
            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: (GlobalStates.overviewOpen || overviewScope.overviewLoaded) && (Config.layout.overview.enable ?? true)
                visible: panelWindow.searchingText === ""
                sourceComponent: DesktopLayout.scrolling ? scrollingComponent : classicComponent
                Component { id: scrollingComponent; OverviewWidget {
                    screen: panelWindow.screen
                    dragController: overviewDrag
                    onSearchRequested: text => overviewScope.openSearch(text)
                } }
                Component { id: classicComponent; ClassicOverviewWidget { screen: panelWindow.screen } }
            }
        }
        function setSearchingText(text) { searchWidget.setSearchingText(text); searchWidget.focusFirstItem(); }
    }

    // Other outputs become drop targets only during a card drag. The original
    // surface keeps the pointer and keyboard grab; these surfaces only draw.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: dropPanel
            required property var modelData
            screen: modelData
            visible: DesktopLayout.scrolling && GlobalStates.overviewOpen && overviewDrag.active
                && modelData.name !== overviewScope.focusedScreen?.name
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:overview-drop"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            Loader {
                active: DesktopLayout.scrolling && overviewScope.overviewLoaded && (Config.layout.overview.enable ?? true)
                anchors.horizontalCenter: parent.horizontalCenter
                y: searchWidget.height - 8
                sourceComponent: OverviewWidget {
                    screen: dropPanel.screen
                    dragController: overviewDrag
                }
            }
        }
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
        function screens(): string {
            return JSON.stringify(overviewDrag.views.filter(view => view.QsWindow.window?.visible)
                .map(view => ({ monitor: view.monitorName, rows: view.geometry() })));
        }
        function state(): string {
            return JSON.stringify({ open: GlobalStates.overviewOpen, search: panelWindow.searchingText !== "",
                overview: GlobalStates.overviewOpen && overviewLoader.visible && overviewLoader.active,
                monitor: overviewScope.focusedScreen?.name, mode: DesktopLayout.scrolling ? "scrolling" : "classic", focused: GlobalFocusGrab.hasActive(searchWidget),
                searchFocused: GlobalFocusGrab.hasActive(searchWidget), dropWorkspace: overviewLoader.item?.dropWorkspace ?? -1,
                selection: overviewLoader.item?.selectedAddress ?? "", workspace: overviewLoader.item?.selectedWorkspace ?? 0,
                query: panelWindow.searchingText, dragging: overviewDrag.active,
                targetMonitor: overviewDrag.targetView?.monitorName ?? "" });
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
