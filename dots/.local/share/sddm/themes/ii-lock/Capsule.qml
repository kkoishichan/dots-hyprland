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
    RectangularShadow {
        anchors.fill: background
        radius: background.radius
        blur: 9
        spread: 1
        offset: Qt.vector2d(0, 1)
        color: root.styleData.shadow
        cached: true
    }
    Rectangle {
        id: background
        anchors.fill: parent
        radius: height / 2
        color: root.styleData.toolbar
    }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
    }
}
