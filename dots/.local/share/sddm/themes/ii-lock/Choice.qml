import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ComboBox {
    id: root
    required property var styleData
    property string symbol
    property real maximumWidth: 160
    property bool compact: false
    implicitWidth: compact ? 40 : Math.min(maximumWidth, label.implicitWidth + 48)
    implicitHeight: 40
    Layout.fillHeight: true
    leftPadding: compact ? 0 : 34
    rightPadding: compact ? 0 : 10
    font.family: styleData.font
    font.pixelSize: 15
    font.variableAxes: ({ "wght": 450, "wdth": 100 })
    textRole: "name"
    valueRole: "name"
    hoverEnabled: true
    Accessible.description: displayText
    indicator: Item {}
    background: Rectangle {
        radius: height / 2
        color: root.down ? root.styleData.fieldActive : root.hovered || root.activeFocus ? root.styleData.fieldHover : "transparent"
        Behavior on color { ColorAnimation { duration: 200 } }
    }
    Symbol {
        anchors.left: root.compact ? undefined : parent.left
        anchors.leftMargin: root.compact ? 0 : 7
        anchors.horizontalCenter: root.compact ? parent.horizontalCenter : undefined
        anchors.verticalCenter: parent.verticalCenter
        styleData: root.styleData
        text: root.symbol
        fill: root.compact ? 0 : 1
    }
    contentItem: Text {
        id: label
        visible: !root.compact
        text: root.displayText
        font: root.font
        color: root.styleData.text
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }
    delegate: ItemDelegate {
        required property int index
        required property string name
        width: list.width
        height: 40
        highlighted: root.highlightedIndex === index
        contentItem: Text {
            text: parent.name
            font: root.font
            color: root.styleData.text
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 12
            color: parent.highlighted ? root.styleData.secondary : "transparent"
        }
    }
    popup: Popup {
        objectName: "choicePopup"
        y: -height - 12
        width: Math.max(root.width, 220)
        padding: 8
        implicitHeight: Math.min(list.contentHeight + 16, 260)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        contentItem: ListView {
            id: list
            clip: true
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            color: root.styleData.toolbar
            radius: 20
            border.color: root.styleData.field
        }
    }
}
