// The lock screen's 56 px toolbar, 8 px padding and 28 px corner radius.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    required property var styleData
    default property alias contents: row.data
    implicitWidth: row.implicitWidth + 16
    implicitHeight: 56
    Rectangle {
        id: background
        anchors.fill: parent
        radius: height / 2
        color: root.styleData.toolbar
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowOpacity: 0.18
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }
    }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
    }
}
