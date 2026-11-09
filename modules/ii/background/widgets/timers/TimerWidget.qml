import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "timers"
    hoverEnabled: true

    property real widgetWidth: 420
    property real cardSpacing: 12
    property real cardHeight: 120
    property real cardWidth: (widgetWidth - cardSpacing * 2) / 3
    property bool isVertical: root.configEntry.vertical ?? false

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    component TimerCard: WidgetCard {
        id: timerCard
        property string icon: ""
        property string value: ""
        property string label: ""
        property bool running: false
        property int shape: MaterialShape.Shape.Cookie12Sided
        property color bgColor: Appearance.colors.colPrimaryContainer
        property color shapeColor: Appearance.colors.colPrimary
        property var onToggle: () => {}
        property var onReset: () => {}
        property real extraContentHeight: 22
        default property alias extraContent: extraSlot.data

        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight + Math.max(0, timerCard.extraContentHeight - 22)
        widget: root
        color: timerCard.bgColor

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: timerCard.onReset()
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: -4

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Item { Layout.fillWidth: true }

                MaterialShapeWrappedMaterialSymbol {
                    shape: timerCard.shape
                    color: timerCard.shapeColor
                    colSymbol: Appearance.colors.colOnPrimary
                    text: timerCard.running ? "pause" : timerCard.icon
                    iconSize: 18
                    fill: 1
                    padding: 6
                    implicitWidth: 34
                    implicitHeight: 34

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: timerCard.onToggle()
                    }
                }
            }

            Item { Layout.fillHeight: true }

            ColumnLayout {
                Layout.leftMargin: 2
                Layout.topMargin: -40
                spacing: -4
                StyledText {
                    text: timerCard.value
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    text: timerCard.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.6
                }
            }

            Item {
                id: extraSlot
                Layout.fillWidth: true
                Layout.preferredHeight: children.length > 0 ? timerCard.extraContentHeight : 0
                Layout.topMargin: children.length > 0 ? 6 : 0
            }
        }
    }

    Grid {
        id: row
        columns: root.isVertical ? 1 : 3
        rows: root.isVertical ? 3 : 1
        spacing: root.cardSpacing

        Behavior on columns {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        // Pomodoro
        TimerCard {
            icon: TimerService.pomodoroBreak ? "coffee" : "visibility"
            value: TimerService.formatSeconds(TimerService.pomodoroSecondsLeft)
            label: TimerService.pomodoroBreak ? "Break" : "Focus"
            running: TimerService.pomodoroRunning
            bgColor: Appearance.colors.colTertiaryContainer
            shapeColor: Appearance.colors.colTertiary
            shape: MaterialShape.Shape.Flower
            onToggle: () => TimerService.togglePomodoro()
            onReset: () => TimerService.resetPomodoro()
        }

        // Stopwatch
        TimerCard {
            icon: TimerService.stopwatchTime > 0 ? "play_arrow" : "timer"
            value: TimerService.formatStopwatchTime(TimerService.stopwatchTime)
            label: "Stopwatch"
            running: TimerService.stopwatchRunning
            shape: MaterialShape.Shape.Sunny
            bgColor: Appearance.colors.colSecondaryContainer
            shapeColor: Appearance.colors.colSecondary
            onToggle: () => TimerService.toggleStopwatch()
            onReset: () => TimerService.stopwatchReset()
            extraContentHeight: 20 + Math.min(TimerService.stopwatchLaps.length, 4) * 14

            ColumnLayout {
                anchors.fill: parent
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    spacing: 4

                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 18
                        radius: Appearance.rounding.small
                        color: TimerService.stopwatchRunning
                            ? ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.85)
                            : ColorUtils.transparentize(Appearance.colors.colErrorContainer, 0.3)
                        opacity: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0
                            || TimerService.stopwatchLaps.length > 0 ? 1 : 0.45

                        StyledText {
                            anchors.centerIn: parent
                            text: TimerService.stopwatchRunning
                                ? Translation.tr("Lap")
                                : Translation.tr("Reset")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0
                                || TimerService.stopwatchLaps.length > 0
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (TimerService.stopwatchRunning)
                                    TimerService.stopwatchRecordLap()
                                else
                                    TimerService.stopwatchReset()
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const count = TimerService.stopwatchLaps.length;
                            return count > 0
                                ? `${count} ${Translation.tr(count === 1 ? "lap" : "laps")}`
                                : Translation.tr("No laps");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.65
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(TimerService.stopwatchLaps.length, 4) * 14
                    clip: true
                    spacing: 0

                    model: ScriptModel {
                        values: {
                            const laps = Array.from(TimerService.stopwatchLaps ?? []);
                            return laps.slice().reverse().map((lapTime, index) => {
                                const originalIndex = laps.length - index - 1;
                                const previousTime = originalIndex > 0 ? laps[originalIndex - 1] : 0;
                                return {
                                    number: originalIndex + 1,
                                    split: Math.max(0, lapTime - previousTime)
                                };
                            });
                        }
                    }

                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        height: 14
                        spacing: 2

                        StyledText {
                            text: `#${modelData.number}`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.6
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: TimerService.formatStopwatchTime(modelData.split)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }

        // Countdown
        TimerCard {
            icon: "hourglass_top"
            value: TimerService.formatSeconds(TimerService.countdownSecondsLeft)
            label: "Countdown"
            running: TimerService.countdownRunning
            shape: MaterialShape.Shape.Bun
            onToggle: () => TimerService.toggleCountdown()
            onReset: () => TimerService.resetCountdown()

            RowLayout {
                anchors.fill: parent
                spacing: 4

                Repeater {
                    model: [1, 5]
                    delegate: Rectangle {
                        required property int modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(Appearance.colors.colOnTertiaryContainer, 0.85)

                        StyledText {
                            anchors.centerIn: parent
                            text: "+" + modelData + "m"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TimerService.addCountdownMinutes(modelData)
                        }
                    }
                }
            }
        }
    }

    WidgetFlipHandle {
        anchorItem: root
        hoverActive: root.containsMouse
        locked: Config.options.background.widgetsLocked
        onClicked: {
            root.isVertical = !root.isVertical
            root.configEntry.vertical = root.isVertical
        }
    }
}
