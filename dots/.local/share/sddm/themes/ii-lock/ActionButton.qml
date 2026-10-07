import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: root
    required property var styleData
    property string symbol
    property bool accent: false
    property string labelText: ""
    implicitWidth: labelText ? buttonContents.implicitWidth + 20 : 40
    implicitHeight: 40
    Layout.fillHeight: true
    padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    Accessible.name: text
    background: Rectangle {
        radius: height / 2
        color: root.accent
            ? (root.down ? root.styleData.primaryActive : root.hovered ? root.styleData.primaryHover : root.styleData.primary)
            : (root.down ? root.styleData.fieldActive : root.hovered || root.activeFocus ? root.styleData.fieldHover : "transparent")
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1] } }
    }
    contentItem: Item {
        Row {
            id: buttonContents
            anchors.centerIn: parent
            spacing: 8
            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                styleData: root.styleData
                text: root.symbol
                fill: root.labelText ? 1 : 0
                iconSize: root.accent ? 24 : 22
                color: !root.enabled ? root.styleData.muted : root.accent ? root.styleData.onPrimary : root.styleData.text
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.labelText.length > 0
                text: root.labelText
                color: root.styleData.text
                font.family: root.styleData.font
                font.pixelSize: 15
                font.variableAxes: ({ "wght": 450, "wdth": 100 })
                renderType: Text.NativeRendering
            }
        }
    }
}
