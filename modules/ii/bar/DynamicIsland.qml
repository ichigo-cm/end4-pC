import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool mirrored: false
    readonly property bool isMacStyle: Config.options.appearance.shellStyle === "macos"
    readonly property color islandContentColor: isMacStyle
        ? (Appearance.m3colors.darkmode ? Appearance.m3colors.m3onBackground : Appearance.m3colors.m3inverseOnSurface)
        : Appearance.colors.colOnLayer0

    readonly property real pillHeight: isMacStyle ? 28 : 32
    readonly property real idleCollapsedWidth: isMacStyle ? 176 : 144
    readonly property real sessionWidth: isMacStyle ? 220 : 164
    property real idleTextContentWidth: 0
    readonly property real idleWidth: Math.max(root.idleCollapsedWidth, root.idleTextContentWidth)
    readonly property real mediaCollapsedWidth: isMacStyle ? 190 : 140
    readonly property real mediaExpandedWidthCap: isMacStyle ? 320 : 220
    property real mediaTextContentWidth: 0
    property bool mediaTrackInfoVisible: isMacStyle || mediaHoverHandler.hovered || mediaTrackChangeTimer.running
    readonly property real mediaExpandedWidth: Math.min(root.mediaExpandedWidthCap, root.mediaTextContentWidth)
    readonly property real mediaWidth: root.mediaTrackInfoVisible ? root.mediaExpandedWidth : root.mediaCollapsedWidth
    readonly property real timerWidth: isMacStyle ? 180 : 130
    readonly property real osdWidth: 132
    readonly property real notificationWidth: isMacStyle ? 300 : 220
    readonly property real batteryWidth: 170
    readonly property real recordingWidth: isMacStyle ? 132 : 112
    readonly property real badgeSize: isMacStyle ? 24 : 32
    readonly property real badgeSpacing: 6
    readonly property bool isMaterial: !isMacStyle && (Config.options.bar.cornerStyle === 3 || Config.options.bar.cornerStyle === 4)
    property bool vertical: Config.options.bar.vertical

    property string manualFocusId: ""

    property bool forceIdle: false

    readonly property var displayedProvider: root.forceIdle ? null : root.activeProvider

    onActiveProviderChanged: {
        if (root.activeProvider && root.alwaysWinIds.includes(root.activeProvider.id)) {
            root.forceIdle = false
        }
    }

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool hasMedia: root.activePlayer !== null
        && ((root.activePlayer.trackTitle ?? "") !== "" || root.activePlayer.isPlaying)
    readonly property var latestNotification: Notifications.popupList.length > 0
        && !Notifications.popupInhibited
        ? Notifications.popupList[Notifications.popupList.length - 1]
        : null
    readonly property bool isRecording: Persistent.states.record.enable
    property string engagedTimerKind: ""
    readonly property bool hasActiveTimer: root.engagedTimerKind !== ""

    function selectRunningTimer() {
        if (TimerService.pomodoroRunning) root.engagedTimerKind = "pomodoro"
        else if (TimerService.countdownRunning) root.engagedTimerKind = "countdown"
        else if (TimerService.stopwatchRunning) root.engagedTimerKind = "stopwatch"
        else root.engagedTimerKind = ""
    }

    function reconcileTimerSelection() {
        if (root.engagedTimerKind !== "countdown"
                || TimerService.countdownRunning
                || TimerService.countdownDuration > 0) return
        root.selectRunningTimer()
    }

    Component.onCompleted: root.selectRunningTimer()

    Connections {
        target: TimerService
        function onPomodoroRunningChanged() { if (TimerService.pomodoroRunning) root.engagedTimerKind = "pomodoro" }
        function onCountdownRunningChanged() {
            if (TimerService.countdownRunning) root.engagedTimerKind = "countdown"
            else Qt.callLater(() => root.reconcileTimerSelection())
        }
        function onCountdownDurationChanged() { Qt.callLater(() => root.reconcileTimerSelection()) }
        function onStopwatchRunningChanged() { if (TimerService.stopwatchRunning) root.engagedTimerKind = "stopwatch" }
    }

    function timerIcon() {
        switch (root.engagedTimerKind) {
            case "pomodoro":  return TimerService.pomodoroBreak ? "coffee" : "visibility"
            case "countdown": return "hourglass_top"
            case "stopwatch": return "timer"
            default:          return "timer"
        }
    }

    function timerValueText() {
        switch (root.engagedTimerKind) {
            case "pomodoro":  return TimerService.formatSeconds(TimerService.pomodoroSecondsLeft)
            case "countdown": return TimerService.formatSeconds(TimerService.countdownSecondsLeft)
            case "stopwatch": return TimerService.formatSeconds(TimerService.stopwatchTime / 100)
            default:          return ""
        }
    }

    function timerRunning() {
        switch (root.engagedTimerKind) {
            case "pomodoro":  return TimerService.pomodoroRunning
            case "countdown": return TimerService.countdownRunning
            case "stopwatch": return TimerService.stopwatchRunning
            default:          return false
        }
    }

    function toggleActiveTimer() {
        switch (root.engagedTimerKind) {
            case "pomodoro":  TimerService.togglePomodoro(); break
            case "countdown": TimerService.toggleCountdown(); break
            case "stopwatch": TimerService.toggleStopwatch(); break
        }
    }

    function resetActiveTimer() {
        switch (root.engagedTimerKind) {
            case "pomodoro":  TimerService.resetPomodoro(); break
            case "countdown": TimerService.resetCountdown(); break
            case "stopwatch": TimerService.stopwatchReset(); break
        }
        root.selectRunningTimer()
    }

    property bool batteryAlertActive: false
    property string batteryAlertKind: "" 
    readonly property int batteryAlertDuration: 4000

    Timer {
        id: batteryAlertTimer
        interval: root.batteryAlertDuration
        repeat: false
        onTriggered: root.batteryAlertActive = false
    }

    Timer {
        id: mediaTrackChangeTimer
        interval: 3000
        repeat: false
    }

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() { mediaTrackChangeTimer.restart() }
        function onTrackArtistChanged() { mediaTrackChangeTimer.restart() }
    }

    function triggerBatteryAlert(kind) {
        root.batteryAlertKind = kind
        root.batteryAlertActive = true
        batteryAlertTimer.restart()
    }

    Connections {
        target: Battery
        function onIsCriticalAndNotChargingChanged() {
            if (Battery.available && Battery.isCriticalAndNotCharging) root.triggerBatteryAlert("critical")
        }
        function onIsLowAndNotChargingChanged() {
            if (Battery.available && Battery.isLowAndNotCharging && !Battery.isCriticalAndNotCharging) root.triggerBatteryAlert("low")
        }
        function onIsPluggedInChanged() {
            if (Battery.available && Battery.isPluggedIn) root.triggerBatteryAlert("charging")
        }
    }

    function batteryStatusText() {
        switch (root.batteryAlertKind) {
            case "critical": return Translation.tr("Critical Battery")
            case "charging": return Translation.tr("Charging")
            default:         return Translation.tr("Low Battery")
        }
    }

    function batteryIcon() {
        if (root.batteryAlertKind === "charging" || Battery.isCharging) return "battery_android_frame_bolt"
        const pct = Battery.percentage
        if (pct <= 0.1) return "battery_android_frame_alert"
        if (pct <= 0.2) return "battery_android_frame_1"
        if (pct <= 0.4) return "battery_android_frame_2"
        if (pct <= 0.6) return "battery_android_frame_3"
        if (pct <= 0.8) return "battery_android_frame_4"
        if (pct < 1)    return "battery_android_frame_5"
        return "battery_android_full"
    }

    function batteryAlertColor() {
        return root.batteryAlertKind === "charging" ? Appearance.m3colors.m3success : Appearance.colors.colError
    }

    readonly property var contentProviders: [
        { id: "session",      active: GlobalStates.diSessionOpen,       component: sessionComponent,      width: root.sessionWidth },
        { id: "notification", active: root.latestNotification !== null, component: notificationComponent, width: root.notificationWidth },
        { id: "battery",      active: root.batteryAlertActive,          component: batteryComponent,      width: root.batteryWidth },
        { id: "osd",          active: GlobalStates.osdVolumeOpen,       component: osdComponent,          width: root.osdWidth },
        { id: "recording",    active: root.isRecording,                 component: recordingComponent,    width: root.recordingWidth },
        { id: "timer",        active: root.hasActiveTimer,              component: timerComponent,        width: root.timerWidth },
        { id: "media",        active: root.hasMedia,                    component: mediaComponent,        width: root.mediaWidth },
    ]

    readonly property var alwaysWinIds: ["session", "notification", "battery", "osd"]

    readonly property var activeOthers: root.contentProviders.filter(p => !root.alwaysWinIds.includes(p.id) && p.active)

    readonly property var activeProvider: {
        const forcedTop = root.contentProviders.find(p => root.alwaysWinIds.includes(p.id) && p.active)
        if (forcedTop) return forcedTop
        if (root.manualFocusId !== "") {
            const forced = root.activeOthers.find(p => p.id === root.manualFocusId)
            if (forced) return forced
        }
        if (root.isMacStyle) {
            const media = root.activeOthers.find(p => p.id === "media")
            if (media) return media
        }
        return root.activeOthers[0] ?? null
    }

    readonly property var badgeProviders: {
        if (root.alwaysWinIds.some(id => root.contentProviders.find(p => p.id === id)?.active)) return []
        return root.activeOthers.filter(p => p.id !== root.activeProvider?.id)
    }

    function iconForProviderId(id) {
        switch (id) {
            case "media":     return "music_note"
            case "recording": return "screen_record"
            case "timer":     return root.timerIcon()
            case "battery":   return root.batteryIcon()
            case "osd":
                switch (GlobalStates.osdIndicatorType) {
                    case "brightness": return Hyprsunset.temperatureActive ? "routine" : "light_mode"
                    case "gamma":      return "wb_twilight"
                    default:           return Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                }
            default: return "circle"
        }
    }

    readonly property string activeContentId: root.displayedProvider?.id ?? "idle"
    readonly property real badgeExtent: !root.vertical && root.badgeProviders.length > 0
        ? root.badgeProviders.length * (root.badgeSpacing + root.badgeSize)
        : 0

    implicitHeight: root.pillHeight
    implicitWidth: (root.displayedProvider?.width ?? root.idleWidth)
        + root.badgeExtent * (root.isMacStyle ? 2 : 1)

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.isMacStyle
                ? (Config.options.hyprland.animations.enable ? 220 : 0)
                : 350
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }

    Rectangle {
        id: pill
        anchors.left: root.isMacStyle ? undefined : parent.left
        anchors.horizontalCenter: root.isMacStyle ? parent.horizontalCenter : undefined
        width: root.displayedProvider?.width ?? root.idleWidth
        height: root.pillHeight
        color: root.isMacStyle ? Appearance.m3colors.m3scrim
            : root.isMaterial || (GlobalStates.barCenterOnly && Config.options.bar.cornerStyle === 0) ? "transparent" : Config.options.bar.followFrameColor
            ? Appearance.getColorFromName(Config.options.bar.frameColor)
            : Appearance.colors.colUiBackground
        radius: height / 2
        border.width: root.isMacStyle ? Appearance.design.hairlineWidth : 0
        border.color: root.isMacStyle ? Appearance.colors.colOutlineVariant : "transparent"
        clip: true
        visible: !root.vertical

        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 1
                leftMargin: 14
                rightMargin: 14
            }
            height: 1
            radius: 1
            color: Appearance.design.glassSpecular
            visible: root.isMacStyle
        }

        Behavior on width {
            NumberAnimation {
                duration: root.isMacStyle
                    ? (Config.options.hyprland.animations.enable ? 220 : 0)
                    : 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        HoverHandler {
            id: mediaHoverHandler
            enabled: !root.isMacStyle && root.hasMedia
        }

        WheelHandler {
            id: idleToggleWheelHandler
            target: pill
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property bool coolingDown: false
            onWheel: (event) => {
                if (coolingDown) return
                coolingDown = true
                idleToggleDebounceTimer.restart()
                root.forceIdle = !root.forceIdle
            }
        }

        Timer {
            id: idleToggleDebounceTimer
            interval: 200
            onTriggered: idleToggleWheelHandler.coolingDown = false
        }

    Loader {
            id: contentLoader
            anchors.fill: parent
            sourceComponent: root.displayedProvider?.component ?? (root.isMacStyle ? macIdleComponent : idleComponent)
            active: !root.vertical
            onSourceComponentChanged: {
                if (root.isMacStyle) opacity = 0
            }

            onLoaded: {
                if (root.isMacStyle) opacity = 1
                if (root.displayedProvider?.id === "session" && item) {
                    item.forceActiveFocus()
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.isMacStyle && Config.options.hyprland.animations.enable ? 140 : 0
                    easing.type: Easing.OutCubic
                }
            }
        }

        Component {
            id: idleComponent
            DiIdle { di: root }
        }

        Component {
            id: macIdleComponent
            Item { }
        }

        Component {
            id: mediaComponent
            DiMedia { di: root }
        }

        Component {
            id: osdComponent
            DiOsd { di: root }
        }

        Component {
            id: notificationComponent
            DiNotifs { di: root }
        }

        Component {
            id: timerComponent
            DiTimers { di: root }
        }

        Component {
            id: sessionComponent
            DiSession { di: root }
        }

        Component {
            id: recordingComponent
            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: root.isMaterial ? 4 : 8
                    rightMargin: 10
                }
                spacing: 6

                Item {
                    id: stopButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 16
                    implicitHeight: 16
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("Stop screen recording")
                    Keys.onReturnPressed: Quickshell.execDetached([Directories.recordScriptPath])
                    Keys.onSpacePressed: Quickshell.execDetached([Directories.recordScriptPath])

                    MaterialSymbol {
                        anchors.fill: parent
                        text: "stop_circle"
                        fill: 1
                        iconSize: root.isMaterial ? 26 : 16
                        color: Appearance.colors.colError
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "transparent"
                        border.width: stopButton.activeFocus ? 1 : 0
                        border.color: Appearance.colors.colError
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([Directories.recordScriptPath])
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Recording")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.islandContentColor
                }
            }
        }

        Component {
            id: batteryComponent
            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 6

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.batteryStatusText()
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.batteryAlertColor()
                }

                Item { Layout.fillWidth: true }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.batteryIcon()
                    fill: 1
                    iconSize: 16
                    color: root.batteryAlertColor()
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: `${Math.round(Battery.percentage * 100)}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: { "tnum": 1 }
                    color: root.batteryAlertColor()
                }
            }
        }
    }

    Row {
        id: badgesRow
        visible: root.badgeProviders.length > 0 && !root.vertical
        anchors {
            left: pill.right
            leftMargin: root.badgeSpacing
            verticalCenter: pill.verticalCenter
        }
        spacing: root.badgeSpacing

        Repeater {
            model: root.badgeProviders
            delegate: Item {
                id: badgeItem
                required property var modelData
                width: root.badgeSize
                height: root.badgeSize

                MaterialShapeWrappedMaterialSymbol {
                    anchors.fill: parent
                    wrappedShape: root.isMacStyle ? MaterialShape.Shape.Circle : MaterialShape.Shape.Cookie7Sided
                    color: root.isMacStyle ? Appearance.m3colors.m3scrim
                        : root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colLayer0
                    colSymbol: root.isMacStyle ? root.islandContentColor
                        : root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                    text: root.iconForProviderId(badgeItem.modelData.id)
                    iconSize: 16
                    fill: 1
                    padding: 4
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.manualFocusId = badgeItem.modelData.id
                }
            }
        }
    }
}
