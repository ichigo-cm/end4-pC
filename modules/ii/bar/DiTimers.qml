import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: diTimersRoot
    required property Item di
    anchors {
        fill: parent
        leftMargin: root.isMaterial ? 4 : 8
        rightMargin: 10
    }
    spacing: 6

    Item {
        id: timerPauseButton
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 16
        implicitHeight: 16
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.timerRunning() ? Translation.tr("Pause timer") : Translation.tr("Resume timer")
        Keys.onReturnPressed: root.toggleActiveTimer()
        Keys.onSpacePressed: root.toggleActiveTimer()

        MaterialSymbol {
            anchors.fill: parent
            text: root.timerRunning() ? "pause" : "play_arrow"
            fill: 1
            iconSize: root.isMaterial ? 24 : 16
            color: root.islandContentColor
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: timerPauseButton.activeFocus ? 1 : 0
            border.color: root.islandContentColor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleActiveTimer()
        }
    }

    Item {
        id: timerStopButton
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 16
        implicitHeight: 16
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Translation.tr("Reset timer")
        Keys.onReturnPressed: root.resetActiveTimer()
        Keys.onSpacePressed: root.resetActiveTimer()

        MaterialSymbol {
            anchors.fill: parent
            text: "stop_circle"
            fill: 1
            iconSize: root.isMaterial ? 24 : 16
            color: root.islandContentColor
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: timerStopButton.activeFocus ? 1 : 0
            border.color: root.islandContentColor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resetActiveTimer()
        }
    }

    Item { Layout.fillWidth: true }

    StyledText {
        visible: root.isMacStyle
        Layout.alignment: Qt.AlignVCenter
        text: root.engagedTimerKind === "pomodoro" ? Translation.tr("Focus")
            : root.engagedTimerKind === "countdown" ? Translation.tr("Timer")
            : Translation.tr("Stopwatch")
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: root.islandContentColor
        opacity: 0.75
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter
        text: root.timerValueText()
        font.pixelSize: Appearance.font.pixelSize.small
        font.features: { "tnum": 1 }
        color: root.islandContentColor
    }
}
