import QtQuick

Text {
    required property var styleData
    property real iconSize: 22
    property real fill: 0
    color: styleData.text
    font.family: styleData.iconFont
    font.pixelSize: iconSize
    font.hintingPreference: Font.PreferNoHinting
    font.weight: Font.Normal + (Font.DemiBold - Font.Normal) * fill
    font.variableAxes: ({ "FILL": fill, "opsz": iconSize })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
