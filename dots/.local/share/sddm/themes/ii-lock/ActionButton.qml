import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: root
    required property var styleData
    property string symbol
    property bool accent: false
    implicitWidth: 40
    implicitHeight: 40
    Layout.fillHeight: true
    padding: 0
    hoverEnabled: true
    Accessible.name: text
    background: Rectangle {
        radius: height / 2
        color: root.accent ? root.styleData.primary : root.down ? root.styleData.secondary : root.hovered || root.activeFocus ? root.styleData.field : "transparent"
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    contentItem: Symbol {
        styleData: root.styleData
        text: root.symbol
        iconSize: 24
        color: !root.enabled ? root.styleData.muted : root.accent ? root.styleData.onPrimary : root.styleData.text
    }
}
