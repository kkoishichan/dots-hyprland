import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item {
    id: root
    readonly property string monitorName: root.QsWindow.window?.screen?.name ?? ""
    readonly property int workspaceId: ScrollingLayout.activeId(monitorName)
    readonly property var activeWindow: ScrollingLayout.focusedWindow(monitorName, workspaceId)

    implicitWidth: colLayout.implicitWidth

    ColumnLayout {
        id: colLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: -4

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.activeWindow?.class ?? Translation.tr("Desktop")

        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            text: root.activeWindow?.title ?? `${Translation.tr("Workspace")} ${ScrollingLayout.position(root.monitorName, workspaceId)}`
        }

    }

}
