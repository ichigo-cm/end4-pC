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
    property color vocalColor: dimColor
    property int textAlignment: Text.AlignLeft
    property real fontScale: 1.0
    property bool animateTransitions: true
    property real lineSpacing: 6
    readonly property string lyricMode: LyricsService.lyricMode
    readonly property bool karaokeEnabled: LyricsService.karaokeMotion
    readonly property bool lineMotionEnabled: root.animateTransitions && root.lyricMode !== "static" && !Config.options.appearance.reducedMotion

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

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: LyricsService.status !== "loading"
                    text: LyricsService.status === "no_info"
                        ? Translation.tr("Play a song to find lyrics")
                        : Translation.tr("Synced lyrics not found")
                    color: root.dimColor
                    font.pixelSize: Appearance.font.pixelSize.small * root.fontScale
                    horizontalAlignment: Text.AlignHCenter
                    Accessible.name: text
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok"
            spacing: root.lineSpacing

            Repeater {
                model: 7
                delegate: ColumnLayout {
                    id: lyricSlot
                    required property int index
                    Layout.fillWidth: true
                    spacing: Math.max(0, 2 * root.fontScale)

                    readonly property int dist: Math.abs(index - LyricsService.before)
                    readonly property string sourceLineText: Config.options.media.showVocalLayers
                        ? (LyricsService.slots[index] ?? "")
                        : (LyricsService.fullSlots[index] ?? LyricsService.slots[index] ?? "")
                    readonly property string romanizedLineText: Config.options.media.showVocalLayers
                        ? (LyricsService.romanizedSlots[index] ?? "")
                        : (LyricsService.fullRomanizedSlots[index] ?? LyricsService.romanizedSlots[index] ?? "")
                    readonly property string vocalLineText: {
                        if (index !== LyricsService.before || !Config.options.media.showVocalLayers) return ""
                        const layers = LyricsService.activeVocalLayers ?? []
                        return layers.map(layer => `${layer.type === "side" ? "↗" : "♪"} ${layer.text}`).join("   ")
                    }
                    readonly property string accessibleVocalLineText: {
                        if (index !== LyricsService.before || !Config.options.media.showVocalLayers) return ""
                        const layers = LyricsService.activeVocalLayers ?? []
                        return layers.map(layer => `${Translation.tr(layer.type === "side" ? "Side vocal" : "Background vocal")}: ${layer.text}`).join(". ")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: root.textAlignment
                        wrapMode: Text.WordWrap
                        text: {
                            if (lyricSlot.index === LyricsService.before && root.karaokeEnabled)
                                return LyricsService.karaokeMarkup(root.activeColor, root.textColor)
                            return lyricSlot.sourceLineText
                        }
                        textFormat: lyricSlot.index === LyricsService.before && root.karaokeEnabled ? Text.StyledText : Text.PlainText
                        Accessible.name: lyricSlot.sourceLineText
                        font.pixelSize: {
                            if (lyricSlot.dist === 0) return Appearance.font.pixelSize.normal * root.fontScale
                            if (lyricSlot.dist === 1) return Appearance.font.pixelSize.small * root.fontScale
                            return Appearance.font.pixelSize.smaller * root.fontScale
                        }
                        opacity: {
                            if (lyricSlot.dist === 0) return 1.0
                            if (lyricSlot.dist === 1) return 0.6
                            if (lyricSlot.dist === 2) return 0.35
                            return 0.15
                        }
                        color: lyricSlot.dist === 0 ? root.activeColor : root.textColor
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: Config.options.media.showRomanization && lyricSlot.romanizedLineText.length > 0
                        text: lyricSlot.romanizedLineText
                        color: root.dimColor
                        font.pixelSize: Appearance.font.pixelSize.smaller * root.fontScale
                        horizontalAlignment: root.textAlignment
                        wrapMode: Text.WordWrap
                        Accessible.name: lyricSlot.romanizedLineText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: lyricSlot.vocalLineText.length > 0
                        text: lyricSlot.vocalLineText
                        color: root.vocalColor
                        font.italic: true
                        font.pixelSize: Appearance.font.pixelSize.smaller * root.fontScale
                        horizontalAlignment: root.textAlignment
                        wrapMode: Text.WordWrap
                        Accessible.name: lyricSlot.accessibleVocalLineText
                    }

                    transform: Translate { id: lineSlide }
                    onSourceLineTextChanged: {
                        if (root.lineMotionEnabled && sourceLineText.length > 0) slideAnim.restart()
                    }
                    SequentialAnimation {
                        id: slideAnim
                        ScriptAction { script: lineSlide.y = 10 * root.fontScale }
                        NumberAnimation { target: lineSlide; property: "y"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        enabled: root.lineMotionEnabled
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
