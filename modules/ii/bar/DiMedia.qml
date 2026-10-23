import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: diMediaRoot
    required property Item di
    anchors.fill: parent

    Rectangle {
        id: mediaMask
        anchors.fill: parent
        color: "transparent"
        radius: height / 2

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: mediaMask.width
                height: mediaMask.height
                radius: mediaMask.radius
            }
        }

        Rectangle {
            id: artMask
            width: root.isMacStyle ? root.pillHeight - 4 : root.isMaterial ? root.pillHeight : root.pillHeight - 8
            height: root.isMacStyle ? root.pillHeight - 4 : root.isMaterial ? root.pillHeight : root.pillHeight - 8
            anchors {
                left: parent.left
                leftMargin: root.isMaterial ? 0 : 4
                verticalCenter: parent.verticalCenter
            }
            radius: root.isMaterial ? Appearance.rounding?.full : Appearance.rounding?.small ?? 8
            color: root.isMacStyle ? ColorUtils.applyAlpha(root.islandContentColor, 0.16) : Appearance.colors.colLayer1
            clip: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artMask.width
                    height: artMask.height
                    radius: artMask.radius
                }
            }

            AnimatedImage {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.activePlayer?.trackArtUrl ?? ""
                playing: true
                sourceSize.width: artMask.width * 2
                sourceSize.height: artMask.height * 2
                visible: (root.activePlayer?.trackArtUrl ?? "") !== ""
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "music_note"
                iconSize: 14
                color: root.isMacStyle ? root.islandContentColor : Appearance.colors.colOnLayer1
                visible: (root.activePlayer?.trackArtUrl ?? "") === ""
            }
        }

        StyledText {
            id: trackTitleMetrics
            visible: false
            text: root.activePlayer?.trackTitle ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
        }
        StyledText {
            id: trackArtistMetrics
            visible: false
            text: root.activePlayer?.trackArtist ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallest
        }

        ColumnLayout {
            id: trackInfoColumn
            anchors {
                left: artMask.right
                leftMargin: 8
                verticalCenter: parent.verticalCenter
                right: mediaControlsRow.visible ? mediaControlsRow.left
                    : (visualizerCanvas.visible ? visualizerCanvas.left
                    : (islandVisualizer.visible ? islandVisualizer.left : parent.right))
                rightMargin: 8
            }
            spacing: root.isMacStyle ? 0 : root.isMaterial ? -2 : -4
            opacity: root.mediaTrackInfoVisible ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.activePlayer?.trackTitle ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.islandContentColor
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }
            StyledText {
                Layout.fillWidth: true
                text: root.activePlayer?.trackArtist ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.islandContentColor
                opacity: 0.7
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }

            Rectangle {
                id: trackProgress
                visible: root.isMacStyle
                    && (root.activePlayer?.positionSupported ?? false)
                    && (root.activePlayer?.lengthSupported ?? false)
                    && (root.activePlayer?.length ?? 0) > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 2
                Layout.maximumHeight: 2
                radius: 1
                color: ColorUtils.applyAlpha(root.islandContentColor, 0.24)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1,
                        (root.activePlayer?.position ?? 0) / Math.max(1, root.activePlayer?.length ?? 1)))
                    height: parent.height
                    radius: parent.radius
                    color: root.islandContentColor
                }
            }

            readonly property real widestLineWidth: Math.max(trackTitleMetrics.implicitWidth, trackArtistMetrics.implicitWidth)

            readonly property real computedContentWidth: artMask.width
                + (root.isMaterial ? 14 : 8)
                + trackInfoColumn.widestLineWidth
                + 12
                + (mediaControlsRow.visible ? mediaControlsRow.implicitWidth
                    : (visualizerCanvas.visible ? visualizerCanvas.width
                    : (islandVisualizer.visible ? islandVisualizer.width : 0)))
                + (root.isMaterial ? 0 : 4)
                + 10

            onComputedContentWidthChanged: root.mediaTextContentWidth = trackInfoColumn.computedContentWidth
            Component.onCompleted: root.mediaTextContentWidth = trackInfoColumn.computedContentWidth
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors {
                right: mediaControlsRow.visible ? mediaControlsRow.left : parent.right
                rightMargin: mediaControlsRow.visible ? 6 : 10
                verticalCenter: parent.verticalCenter
            }
            width: root.isMaterial ? 60 : 50
            height: root.isMaterial ? root.pillHeight * 1.5 : root.pillHeight * 0.85
            live: root.activePlayer?.isPlaying
            points: GlobalStates.visualizerPoints
            maxVisualizerValue: 1000
            smoothing: 2
            color: root.islandContentColor
            visible: !mediaControlsRow.visible && Config.options.bar.dynamicIsland.visualizerStyle === "wave"
        }

        Visualizer {
            id: islandVisualizer
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            height: root.isMaterial ? root.pillHeight * 1.5 : root.pillHeight * 0.85
            vertical: false
            isMaterial: false
            barCount: 5
            dotSize: 3
            dotSpacing: 3
            maxBarHeight: root.isMaterial ? root.pillHeight * 1.5 : root.pillHeight * 0.85
            barColor: root.islandContentColor
            visible: !mediaControlsRow.visible
                && Config.options.bar.dynamicIsland.visualizerStyle === "dots"
        }

        RowLayout {
            id: mediaControlsRow
            anchors {
                right: parent.right
                rightMargin: root.isMaterial ? 4 : 8
                verticalCenter: parent.verticalCenter
            }
            spacing: root.isMacStyle ? 4 : root.isMaterial ? -2 : -4
            visible: root.isMacStyle
                ? ((root.activePlayer?.canGoPrevious ?? false)
                    || (root.activePlayer?.canTogglePlaying ?? false)
                    || (root.activePlayer?.canGoNext ?? false))
                : Config.options.bar.dynamicIsland.showMediaControls

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 24
                implicitHeight: 24
                visible: root.activePlayer?.canGoPrevious ?? false
                activeFocusOnTab: root.isMacStyle && visible
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Previous track")
                Keys.onReturnPressed: MprisController.previous()
                Keys.onSpacePressed: MprisController.previous()

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "transparent"
                    border.width: parent.activeFocus ? 1 : 0
                    border.color: root.islandContentColor
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    fill: 1
                    iconSize: root.isMaterial ? 20 : 16
                    color: root.islandContentColor
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.previous()
                }
            }

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 24
                implicitHeight: 24
                visible: root.activePlayer?.canTogglePlaying ?? false
                activeFocusOnTab: root.isMacStyle && visible
                Accessible.role: Accessible.Button
                Accessible.name: root.activePlayer?.isPlaying
                    ? Translation.tr("Pause") : Translation.tr("Play")
                Keys.onReturnPressed: {
                    if (MprisController.canTogglePlaying) MprisController.togglePlaying()
                }
                Keys.onSpacePressed: {
                    if (MprisController.canTogglePlaying) MprisController.togglePlaying()
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "transparent"
                    border.width: parent.activeFocus ? 1 : 0
                    border.color: root.islandContentColor
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.activePlayer?.isPlaying ? "pause" : "play_arrow"
                    fill: 1
                    iconSize: root.isMaterial ? 20 : 18
                    color: root.islandContentColor
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (MprisController.canTogglePlaying) MprisController.togglePlaying()
                    }
                }
            }

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 24
                implicitHeight: 24
                visible: root.activePlayer?.canGoNext ?? false
                activeFocusOnTab: root.isMacStyle && visible
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Next track")
                Keys.onReturnPressed: MprisController.next()
                Keys.onSpacePressed: MprisController.next()

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "transparent"
                    border.width: parent.activeFocus ? 1 : 0
                    border.color: root.islandContentColor
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_next"
                    fill: 1
                    iconSize: root.isMaterial ? 20 : 16
                    color: root.islandContentColor
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.next()
                }
            }
        }
    }
}
