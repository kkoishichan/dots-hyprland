import QtQuick

Text {
    required property var styleData
    property real iconSize: 22
    color: styleData.text
    font.family: styleData.iconFont
    font.pixelSize: iconSize
    font.weight: Font.Medium
    font.variableAxes: ({ "FILL": 1, "opsz": iconSize })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
