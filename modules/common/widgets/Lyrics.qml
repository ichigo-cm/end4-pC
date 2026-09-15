pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft

    implicitWidth: 200
    implicitHeight: 200

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status !== "ok"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 48
                    implicitHeight: 48

                    MaterialLoadingIndicator {
                        anchors.fill: parent
                        loading: LyricsService.status === "loading"
                        colBg: root.indicatorColor
                        colShape: root.indicatorShapeColor
                        implicitSize: 48
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LyricsService.restartLyrics()
                    }
                }
            }
        }

        ListView {
            id: lyricViewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok"
            clip: true
            model: LyricsService.lyricsLines
            currentIndex: Math.max(0, LyricsService.activeIndex)
            preferredHighlightBegin: height / 2 - 20
            preferredHighlightEnd: height / 2 + 20
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 420
            highlightMoveVelocity: -1
            maximumFlickVelocity: 0
            boundsBehavior: Flickable.StopAtBounds

            delegate: StyledText {
                id: lyricLine
                required property int index
                required property var modelData
                width: lyricViewport.width
                horizontalAlignment: root.textAlignment
                wrapMode: Text.WordWrap
                text: modelData.text || "♪"
                readonly property int dist: Math.abs(index - lyricViewport.currentIndex)
                font.pixelSize: dist === 0
                    ? Appearance.font.pixelSize.normal
                    : dist === 1 ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.smaller
                font.weight: dist === 0 ? Font.DemiBold : Font.Normal
                opacity: dist === 0 ? 1 : dist === 1 ? 0.62 : dist === 2 ? 0.34 : 0.14
                scale: dist === 0 ? 1.035 : dist === 1 ? 1.01 : 1
                transformOrigin: Item.Left
                color: dist === 0 ? root.activeColor : root.textColor
                Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
            }
        }
    }
}
