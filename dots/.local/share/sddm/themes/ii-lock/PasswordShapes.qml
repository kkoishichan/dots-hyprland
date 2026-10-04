// Shape order and motion adapted from illogical-impulse PasswordChars.qml.
// Paths are exported from the existing Apache-2.0 Material shape library.
import QtQuick
import QtQuick.Shapes
import "PasswordShapePaths.js" as Shapes

Item {
    id: root
    required property var styleData
    required property int count
    required property int cursorPosition
    property int selectionStart: 0
    property int selectionEnd: 0
    property bool cursorVisible: true
    clip: true
    Item {
        id: strip
        x: Math.min(0, root.width - Math.max(root.count, root.cursorPosition + 1) * 20)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(root.count, 1) * 20
        height: 20
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Repeater {
            model: root.count
            delegate: Item {
                id: glyph
                required property int index
                x: index * 20
                width: 20
                height: 20
                property bool selected: index >= root.selectionStart && index < root.selectionEnd
                property color animatedColor: root.styleData.primary
                Rectangle {
                    anchors.fill: parent
                    color: glyph.selected ? root.styleData.secondary : "transparent"
                }
                Item {
                    id: animationBox
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    scale: 0.5
                    opacity: 0
                    Shape {
                        width: 1
                        height: 1
                        transform: Scale { xScale: 18; yScale: 18 }
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: glyph.selected ? root.styleData.onSecondary : glyph.animatedColor
                            PathSvg { path: Shapes.paths[glyph.index % Shapes.paths.length] }
                        }
                    }
                }
                ParallelAnimation {
                    running: true
                    NumberAnimation { target: animationBox; property: "opacity"; to: 1; duration: 50 }
                    NumberAnimation { target: animationBox; property: "scale"; to: 1; duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] }
                    ColorAnimation { target: glyph; property: "animatedColor"; to: root.styleData.text; duration: 1000 }
                }
            }
        }
        Rectangle {
            x: root.cursorPosition * 20
            width: 2
            height: 20
            color: root.styleData.primary
            visible: root.cursorVisible
            Behavior on x { NumberAnimation { duration: 160 } }
        }
    }
}
