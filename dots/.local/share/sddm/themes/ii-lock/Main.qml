// illogical-impulse's lock screen adapted to SDDM. GPL-3.0.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root
    objectName: "iiSddmRoot"
    width: 1920
    height: 1080
    color: themeStyle.surface
    property bool authenticating: false
    property bool loginFailed: false
    property date now: new Date()
    property real entrance: 0
    property real entranceScale: 0.9
    readonly property string selectedUser: users.count ? users.currentValue || userModel.lastUser : manualUser.text
    readonly property real fitScale: Math.min(1, (width - 32) / (leftCapsule.width + mainCapsule.width + rightCapsule.width + 20))
    Style { id: themeStyle }

    Component.onCompleted: {
        entrance = 1;
        entranceScale = 1;
        password.forceActiveFocus();
    }
    Behavior on entrance { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1] } }
    Behavior on entranceScale { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] } }
    function submit() {
        if (authenticating || !selectedUser || sessions.currentIndex < 0) return;
        authenticating = true;
        loginFailed = false;
        clearPassword.stop();
        sddm.login(selectedUser, password.text, sessions.currentIndex);
        password.clear();
    }
    function resetFailure() {
        authenticating = false;
        loginFailed = true;
        password.clear();
        shake.restart();
        password.forceActiveFocus();
    }
    Connections {
        target: sddm
        function onLoginFailed() { root.resetFailure(); }
        function onLoginSucceeded() { password.clear(); }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer { id: clearPassword; interval: 10000; onTriggered: password.clear() }

    Item {
        anchors.fill: parent
        clip: true
        Image {
            id: wallpaper
            anchors.centerIn: parent
            width: parent.width * config.realValue("wallpaperZoom")
            height: parent.height * config.realValue("wallpaperZoom")
            source: config.background
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: !config.boolValue("blurEnabled")
            sourceSize.width: Math.ceil(width)
            sourceSize.height: Math.ceil(height)
        }
        GaussianBlur {
            anchors.fill: wallpaper
            source: wallpaper
            scale: config.realValue("blurZoom")
            radius: config.realValue("blurRadius")
            samples: Math.ceil(radius) * 2 + 1
            visible: config.boolValue("blurEnabled")
            cached: true
        }
        Rectangle { anchors.fill: parent; color: themeStyle.scrim; visible: config.boolValue("blurEnabled") }
    }
    MouseArea {
        anchors.fill: parent
        onPressed: password.forceActiveFocus()
    }

    Column {
        id: clock
        anchors.centerIn: parent
        spacing: 10
        opacity: root.entrance
        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            ClockLabel {
                id: clockTime
                objectName: "clockTime"
                Layout.fillWidth: true
                text: config.boolValue("clockVertical") ? Qt.locale().toString(root.now, config.timeFormat).split(":")[0].padStart(2, "0") : Qt.locale().toString(root.now, config.timeFormat)
                font.family: themeStyle.clockFont
                font.pixelSize: config.realValue("clockSize")
                font.weight: config.intValue("clockWeight")
                font.variableAxes: ({"wdth": config.realValue("clockWidth"), "ROND": config.realValue("clockRoundness")})
            }
            ClockLabel {
                Layout.fillWidth: true
                Layout.topMargin: -40
                visible: config.boolValue("clockVertical")
                text: Qt.locale().toString(root.now, config.timeFormat).split(":")[1]?.split(" ")[0].padStart(2, "0") ?? ""
                font: clockTime.font
            }
            ClockLabel {
                objectName: "dateLabel"
                Layout.fillWidth: true
                Layout.topMargin: -20
                visible: config.boolValue("showDate")
                text: Qt.locale().toString(root.now, config.dateFormat)
            }
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: config.boolValue("showLockedText")
            implicitWidth: lockStatus.width + 10
            implicitHeight: lockStatus.height + 10
            Row {
                id: lockStatus
                anchors.centerIn: parent
                spacing: 4
                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    styleData: themeStyle
                    text: "lock"
                    color: themeStyle.clockText
                    iconSize: 22
                    style: Text.Raised
                    styleColor: themeStyle.shadow
                }
                ClockLabel {
                    objectName: "lockStatusLabel"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "已锁定"
                    font.pixelSize: 17
                    font.weight: Font.Normal
                }
            }
        }
    }

    component ClockLabel: Text {
        color: themeStyle.clockText
        font.family: themeStyle.dateFont
        font.pixelSize: 20
        font.weight: 350
        font.styleName: ""
        font.variableAxes: ({})
        font.hintingPreference: Font.PreferDefaultHinting
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        style: Text.Raised
        styleColor: themeStyle.shadow
    }

    Item {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: mainCapsule.width
        height: 56
        scale: root.fitScale * root.entranceScale
        opacity: root.entrance
        transformOrigin: Item.Bottom
        Capsule {
            id: mainCapsule
            objectName: "passwordCapsule"
            styleData: themeStyle
            anchors.centerIn: parent
            TextField {
                id: password
                objectName: "passwordField"
                implicitWidth: 200
                Layout.fillHeight: true
                Layout.rightMargin: -Layout.leftMargin
                padding: 10
                font.family: themeStyle.font
                font.pixelSize: 15
                font.variableAxes: ({ "wght": 450, "wdth": 100 })
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                placeholderText: root.loginFailed ? "密码错误" : keyboard.capsLock ? "大写锁定已开启" : "输入密码"
                placeholderTextColor: themeStyle.muted
                color: config.boolValue("materialShapeChars") ? "transparent" : themeStyle.text
                selectionColor: config.boolValue("materialShapeChars") ? "transparent" : themeStyle.secondary
                selectedTextColor: config.boolValue("materialShapeChars") ? "transparent" : themeStyle.onSecondary
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                enabled: !root.authenticating
                selectByMouse: true
                clip: true
                Accessible.name: "密码"
                background: Rectangle { color: themeStyle.field; radius: height / 2 }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: password.width - 8; height: password.height; radius: height / 2 }
                }
                cursorDelegate: Rectangle {
                    width: 2
                    visible: !config.boolValue("materialShapeChars")
                    color: themeStyle.primary
                }
                onTextChanged: {
                    if (text.length) root.loginFailed = false;
                    clearPassword.restart();
                }
                onAccepted: root.submit()
                Keys.onEscapePressed: clear()
                PasswordShapes {
                    anchors.fill: parent
                    anchors.leftMargin: password.padding
                    anchors.rightMargin: password.padding
                    styleData: themeStyle
                    count: password.text.length
                    cursorPosition: password.cursorPosition
                    selectionStart: password.selectionStart
                    selectionEnd: password.selectionEnd
                    cursorVisible: password.activeFocus && password.enabled
                    visible: config.boolValue("materialShapeChars")
                }
            }
            ActionButton {
                objectName: "loginButton"
                styleData: themeStyle
                symbol: "arrow_right_alt"
                text: "登录"
                accent: true
                enabled: !root.authenticating && root.selectedUser.length > 0 && sessions.currentIndex >= 0
                onClicked: root.submit()
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: password; property: "Layout.leftMargin"; to: -30; duration: 50 }
                NumberAnimation { target: password; property: "Layout.leftMargin"; to: 30; duration: 50 }
                NumberAnimation { target: password; property: "Layout.leftMargin"; to: -15; duration: 40 }
                NumberAnimation { target: password; property: "Layout.leftMargin"; to: 15; duration: 40 }
                NumberAnimation { target: password; property: "Layout.leftMargin"; to: 0; duration: 30 }
            }
        }
        Capsule {
            id: leftCapsule
            styleData: themeStyle
            anchors.right: mainCapsule.left
            anchors.rightMargin: 10
            anchors.top: mainCapsule.top
            Choice {
                id: users
                objectName: "userSelector"
                styleData: themeStyle
                symbol: "account_circle"
                maximumWidth: 130
                model: userModel
                currentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
                visible: count > 0
                enabled: !root.authenticating
                Accessible.name: "用户"
                onActivated: { password.clear(); password.forceActiveFocus(); }
            }
            TextField {
                id: manualUser
                visible: users.count === 0
                implicitWidth: 120
                Layout.fillHeight: true
                placeholderText: "用户名"
                font.family: themeStyle.font
                color: themeStyle.text
                background: Rectangle { radius: 20; color: themeStyle.field }
            }
            Choice {
                id: sessions
                objectName: "sessionSelector"
                styleData: themeStyle
                symbol: "desktop_windows"
                maximumWidth: 240
                model: sessionModel
                currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
                enabled: !root.authenticating
                Accessible.name: "桌面会话"
                onActivated: password.forceActiveFocus()
            }
            ActionButton {
                objectName: "keyboardButton"
                styleData: themeStyle
                symbol: "keyboard_alt"
                text: "切换键盘布局"
                labelText: keyboard.layouts[keyboard.currentLayout]?.shortName?.toUpperCase() ?? ""
                visible: keyboard.enabled && keyboard.layouts.length > 0
                enabled: !root.authenticating
                onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
            }
        }
        Capsule {
            id: rightCapsule
            styleData: themeStyle
            anchors.left: mainCapsule.right
            anchors.leftMargin: 10
            anchors.top: mainCapsule.top
            Battery { styleData: themeStyle; Layout.leftMargin: visible ? 10 : 0; Layout.rightMargin: visible ? 10 : 0 }
            ActionButton { objectName: "sleepButton"; styleData: themeStyle; symbol: "dark_mode"; text: "睡眠"; enabled: sddm.canSuspend && !root.authenticating; onClicked: sddm.suspend() }
            ActionButton { objectName: "powerButton"; styleData: themeStyle; symbol: "power_settings_new"; text: "关机"; enabled: sddm.canPowerOff && !root.authenticating; onClicked: sddm.powerOff() }
            ActionButton { objectName: "rebootButton"; styleData: themeStyle; symbol: "restart_alt"; text: "重启"; enabled: sddm.canReboot && !root.authenticating; onClicked: sddm.reboot() }
        }
    }
}
