import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property HyprlandMonitor monitor
    property string monitorName: monitor?.name ?? ""
    readonly property var liveMonitorData: HyprlandData.monitors.find(m => m.name === monitorName)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int currentWorkspaceId: liveMonitorData?.activeWorkspace?.id ?? monitor?.activeWorkspace?.id ?? 1
    // Match HyprlandData's supported range; temporary IDs must not shift the bar.
    readonly property int activeWorkspace: currentWorkspaceId >= 1 && currentWorkspaceId < 1000000 ? currentWorkspaceId : 1
    readonly property bool currentWorkspaceNotFake: activeWindow?.activated ?? false // Active empty workspace = fake. At least, that's how I like to call it.
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeWorkspace
    readonly property int shownCount: C.Config.layout.bar.workspaces.shown
    readonly property int group: Math.floor((activeWorkspace - 1) / shownCount)
    readonly property var specialWorkspace: liveMonitorData?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name?.replace("special:", "") ?? ""
    readonly property bool specialWorkspaceActive: specialWorkspaceName !== ""

    // Use the same refreshed snapshot for occupancy and app icons.
    readonly property list<bool> occupied: Array.from({length: shownCount}, (_, index) =>
        HyprlandData.windowList.some(win => win.workspace?.id === getWorkspaceIdAt(index)))
    readonly property list<var> biggestWindow: Array.from({length: shownCount}, (_, index) =>
        HyprlandData.biggestWindowForWorkspace(getWorkspaceIdAt(index)))

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1;
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index);
    }

}
