import Quickshell.Io

JsonObject {
    property JsonObject autoHide: JsonObject {
        property bool enable: false
        property int hoverRegionWidth: 2
        property bool pushWindows: false
        property JsonObject showWhenPressingSuper: JsonObject {
            property bool enable: true
            property int delay: 140
        }
    }
    property bool bottom: false // Instead of top
    property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
    property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
    property bool borderless: false // true for no grouping of items
    property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
    property bool showBackground: true
    property bool verbose: true
    property bool vertical: false
    property JsonObject resources: JsonObject {
        property bool alwaysShowSwap: true
        property bool alwaysShowCpu: true
        property int memoryWarningThreshold: 95
        property int swapWarningThreshold: 85
        property int cpuWarningThreshold: 90
    }
    property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
    property JsonObject utilButtons: JsonObject {
        property bool showScreenSnip: true
        property bool showColorPicker: false
        property bool showMicToggle: false
        property bool showKeyboardToggle: true
        property bool showDarkModeToggle: true
        property bool showPerformanceProfileToggle: false
        property bool showScreenRecord: false
    }
    property JsonObject workspaces: JsonObject {
        property bool monochromeIcons: true
        property int shown: 10
        property bool showAppIcons: true
        property bool alwaysShowNumbers: false
        property int showNumberDelay: 300 // milliseconds
        property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
        property bool useNerdFont: false
    }
    property JsonObject weather: JsonObject {
        property bool enable: false
        property bool enableGPS: true // gps based location
        property string city: "" // When 'enableGPS' is false
        property bool useUSCS: false // Instead of metric (SI) units
        property int fetchInterval: 10 // minutes
    }
    property JsonObject indicators: JsonObject {
        property JsonObject notifications: JsonObject {
            property bool showUnreadCount: false
        }
    }
    property JsonObject tooltips: JsonObject {
        property bool clickToShow: false
    }
}
