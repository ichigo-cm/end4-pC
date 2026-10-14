pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    required property var screen
    configEntryName: "commandCenter"
    hoverEnabled: true
    implicitWidth: 690
    implicitHeight: 430
    readonly property var player: MprisController.activePlayer
    readonly property int activeWorkspace: Math.max(1, WM.monitorFor(root.screen)?.activeWorkspace?.id ?? 1)
    readonly property string greeting: DateTime.hour24 < 12 ? "GOOD MORNING" : DateTime.hour24 < 18 ? "GOOD AFTERNOON" : "GOOD EVENING"
    readonly property string trackTitle: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Nothing playing"
    readonly property string trackArtist: root.player?.trackArtist ?? "Your desktop, at a glance"

    Component.onCompleted: ResourceUsage.consumers++
    Component.onDestruction: ResourceUsage.consumers--

    function launchConfigured(command) {
        if (command && command.trim().length > 0)
            Quickshell.execDetached(["bash", "-lc", command])
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        widget: root
        tint: Appearance.colors.colLayer0
        tintOpacity: 0.68
        clip: true

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.92) }
                GradientStop { position: 0.55; color: "transparent" }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colTertiary, 0.94) }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // Header: time/date and live desktop identity.
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: 16
                    color: Appearance.colors.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "space_dashboard"
                        iconSize: 25
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.greeting + "  /  DESK COMMAND CENTER"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: DateTime.longDate
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                    }
                }
                ColumnLayout {
                    spacing: -4
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: DateTime.time
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: `${Weather.data?.city || "WEATHER"}  ·  ${Weather.data?.temp ?? "--°"}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Compact, color-coded live telemetry.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TelemetryCard {
                    Layout.fillWidth: true
                    title: "PROCESSOR"
                    icon: "memory_alt"
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                    progress: Math.max(0, Math.min(1, ResourceUsage.cpuUsage))
                    accent: Appearance.colors.colPrimary
                    subtext: ResourceUsage.cpuTemp > 0 ? `${Math.round(ResourceUsage.cpuTemp)}°C` : "LIVE LOAD"
                    history: ResourceUsage.cpuUsageHistory
                }
                TelemetryCard {
                    Layout.fillWidth: true
                    title: "MEMORY"
                    icon: "developer_board"
                    value: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
                    progress: Math.max(0, Math.min(1, ResourceUsage.memoryUsedPercentage))
                    accent: Appearance.colors.colSecondary
                    subtext: `${ResourceUsage.maxAvailableMemoryString} TOTAL`
                    history: ResourceUsage.memoryUsageHistory
                }
                TelemetryCard {
                    Layout.fillWidth: true
                    title: Battery.available ? "BATTERY" : "STORAGE"
                    icon: Battery.available ? (Battery.isCharging ? "battery_charging_full" : "battery_full") : "hard_drive"
                    value: Battery.available ? `${Math.round(Battery.percentage * 100)}%` : `${Math.round(ResourceUsage.diskUsedPercentage * 100)}%`
                    progress: Math.max(0, Math.min(1, Battery.available ? Battery.percentage : ResourceUsage.diskUsedPercentage))
                    accent: Appearance.colors.colTertiary
                    subtext: Battery.available ? (Battery.isCharging ? "CHARGING" : "ON BATTERY") : "DISK USED"
                    history: Battery.available ? [] : ResourceUsage.diskUsageHistory
                }
            }

            // Workspace navigator and media deck.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: 22
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.25)
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.72)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 9
                        RowLayout {
                            Layout.fillWidth: true
                            MaterialSymbol { text: "grid_view"; iconSize: 19; color: Appearance.colors.colPrimary }
                            StyledText {
                                Layout.fillWidth: true
                                text: "WORKSPACES"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: `ACTIVE 0${root.activeWorkspace}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Jump straight into a space"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 7
                            Repeater {
                                model: [1, 2, 3, 4, 5]
                                delegate: Rectangle {
                                    id: workspaceTile
                                    required property int modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 16
                                    color: workspaceTile.modelData === root.activeWorkspace
                                        ? Appearance.colors.colPrimaryContainer
                                        : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.24)
                                    border.width: workspaceTile.modelData === root.activeWorkspace ? 1 : 0
                                    border.color: Appearance.colors.colPrimary
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: workspaceTile.modelData === root.activeWorkspace ? "radio_button_checked" : "radio_button_unchecked"
                                            iconSize: 16
                                            color: workspaceTile.modelData === root.activeWorkspace ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: `0${workspaceTile.modelData}`
                                            font.pixelSize: 22
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WM.switchWorkspace(workspaceTile.modelData)
                                    }
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            MaterialSymbol { text: "notifications"; iconSize: 15; color: Notifications.unread > 0 ? Appearance.colors.colTertiary : Appearance.colors.colSubtext }
                            StyledText {
                                Layout.fillWidth: true
                                text: Notifications.unread > 0 ? `${Notifications.unread} unread notifications` : "All caught up"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            RippleButton {
                                implicitWidth: 35
                                implicitHeight: 30
                                buttonRadius: 12
                                toggled: Notifications.silent
                                onClicked: Notifications.silent = !Notifications.silent
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: Notifications.silent ? "notifications_off" : "notifications_active"
                                    iconSize: 17
                                    color: Notifications.silent ? Appearance.colors.colTertiary : Appearance.colors.colOnLayer1
                                }
                                StyledToolTip { text: Notifications.silent ? "Turn notifications back on" : "Enable focus mode (mute notifications)" }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: 22
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.25)
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.72)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            MaterialSymbol { text: "graphic_eq"; iconSize: 19; color: Appearance.colors.colTertiary }
                            StyledText {
                                Layout.fillWidth: true
                                text: "NOW PLAYING"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                                color: Appearance.colors.colOnLayer1
                            }
                            Rectangle {
                                implicitWidth: 9; implicitHeight: 9; radius: 5
                                color: root.player?.isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                            }
                        }
                        Item { Layout.fillHeight: true }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.trackTitle
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.trackArtist
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            RippleButton {
                                implicitWidth: 39; implicitHeight: 39; buttonRadius: 15
                                enabled: root.player !== null
                                onClicked: root.player?.previous()
                                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_previous"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
                            }
                            RippleButton {
                                implicitWidth: 48; implicitHeight: 48; buttonRadius: 18
                                enabled: root.player !== null
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                onClicked: root.player?.togglePlaying()
                                contentItem: MaterialSymbol { anchors.centerIn: parent; text: root.player?.isPlaying ? "pause" : "play_arrow"; iconSize: 24; color: Appearance.colors.colOnPrimary }
                            }
                            RippleButton {
                                implicitWidth: 39; implicitHeight: 39; buttonRadius: 15
                                enabled: root.player !== null
                                onClicked: root.player?.next()
                                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_next"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            // Direct system actions use the user's configured app commands.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                QuickAction {
                    Layout.fillWidth: true
                    actionIcon: "terminal"
                    label: "TERMINAL"
                    description: "Open terminal"
                    onTriggered: root.launchConfigured(Config.options.apps.terminal)
                }
                QuickAction {
                    Layout.fillWidth: true
                    actionIcon: "tune"
                    label: "MIXER"
                    description: "Open volume mixer"
                    onTriggered: root.launchConfigured(Config.options.apps.volumeMixer)
                }
                QuickAction {
                    Layout.fillWidth: true
                    actionIcon: "monitor_heart"
                    label: "PROCESSES"
                    description: "Open task manager"
                    onTriggered: root.launchConfigured(Config.options.apps.taskManager)
                }
                QuickAction {
                    Layout.fillWidth: true
                    actionIcon: TimerService.pomodoroBreak ? "coffee" : "timer"
                    label: TimerService.pomodoroRunning ? "PAUSE FOCUS" : "START FOCUS"
                    description: `${TimerService.pomodoroBreak ? "BREAK" : "FOCUS"} · ${TimerService.formatSeconds(TimerService.pomodoroSecondsLeft)}`
                    altAction: () => TimerService.resetPomodoro()
                    onTriggered: TimerService.togglePomodoro()
                    StyledToolTip { text: "Click to start or pause · right-click to reset" }
                }
                QuickAction {
                    Layout.fillWidth: true
                    actionIcon: "lock"
                    label: "LOCK"
                    description: "Lock this session"
                    onTriggered: Session.lock()
                }
            }
        }
    }

    component TelemetryCard: Rectangle {
        id: telemetry
        property string title: ""
        property string icon: ""
        property string value: "--"
        property real progress: 0
        property color accent: Appearance.colors.colPrimary
        property string subtext: ""
        property var history: []
        implicitHeight: 78
        radius: 18
        color: ColorUtils.transparentize(accent, 0.88)
        border.width: 1
        border.color: ColorUtils.transparentize(accent, 0.72)
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 9
            anchors.bottomMargin: 9
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol { text: telemetry.icon; iconSize: 16; color: telemetry.accent }
                StyledText {
                    Layout.fillWidth: true
                    text: telemetry.title
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: telemetry.value
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: ColorUtils.transparentize(telemetry.accent, 0.7)
                    Rectangle {
                        width: parent.width * telemetry.progress
                        height: parent.height
                        radius: parent.radius
                        color: telemetry.accent
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }
                Canvas {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 14
                    property var values: telemetry.history
                    onValuesChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (!values || values.length < 2) return
                        ctx.beginPath()
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = telemetry.accent
                        for (let i = 0; i < values.length; i++) {
                            const x = i / (values.length - 1) * width
                            const y = height - Math.max(0, Math.min(1, values[i])) * height
                            if (i === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: telemetry.subtext
                font.pixelSize: 8
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
        }
    }

    component QuickAction: RippleButton {
        id: action
        property string actionIcon: ""
        property string label: ""
        property string description: ""
        signal triggered()
        implicitHeight: 42
        buttonRadius: 15
        onClicked: action.triggered()
        contentItem: RowLayout {
            spacing: 7
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: action.actionIcon
                iconSize: 17
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: action.label
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.4
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: action.description
                    font.pixelSize: 8
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
    }
}
