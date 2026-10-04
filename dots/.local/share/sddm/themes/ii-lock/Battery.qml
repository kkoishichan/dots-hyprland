import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property var styleData
    property int percentage: -1
    property bool charging: false
    visible: percentage >= 0
    spacing: 4
    function read(path, callback) {
        if (!path) return;
        const request = new XMLHttpRequest();
        request.open("GET", path);
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE && (request.status === 0 || request.status === 200)) callback(request.responseText.trim());
        };
        request.send();
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.read(config.batteryCapacityFile, function(value) { const n = Number(value); root.percentage = value.length && Number.isFinite(n) ? Math.max(0, Math.min(100, n)) : -1; });
            root.read(config.batteryStatusFile, function(value) { root.charging = value === "Charging"; });
        }
    }
    Symbol { styleData: root.styleData; text: root.charging ? "bolt" : "battery_android_full"; color: root.percentage < 20 && !root.charging ? root.styleData.error : root.styleData.text }
    Text { text: root.percentage; color: root.styleData.text; font.family: root.styleData.font; font.pixelSize: 15 }
}
