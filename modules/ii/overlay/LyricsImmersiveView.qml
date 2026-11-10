pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Item {
    id: root
    readonly property var player: MprisController.activePlayer

    component ControlButton: RippleButton {
        id: controlButton
        property string symbol: ""
        property string label: ""
        property var callback
        implicitWidth: 52
        implicitHeight: 52
        buttonRadius: 26
        Accessible.name: label
        colBackground: Qt.rgba(1, 1, 1, 0.12)
        colBackgroundHover: Qt.rgba(1, 1, 1, 0.2)
        colRipple: Qt.rgba(1, 1, 1, 0.28)
        downAction: () => { if (callback) callback(); }
        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.large
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            text: controlButton.symbol
        }
    }

    Loader {
        active: GlobalStates.lyricsFullscreenOpen
        sourceComponent: PanelWindow {
            id: immersiveWindow
            readonly property color artAccent: colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary
            visible: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:immersiveLyrics"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0
            }

            Image {
                id: albumArtBackground
                anchors.fill: parent
                source: GlobalStates.lyricsFullscreenOpen && Config.options.media.dynamicLyricsBackground ? (root.player?.trackArtUrl ?? "") : ""
                sourceSize.width: 1100
                sourceSize.height: 1100
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: status === Image.Ready
            }

            FastBlur {
                anchors.fill: parent
                source: albumArtBackground
                radius: 72
                transparentBorder: false
                visible: Config.options.media.dynamicLyricsBackground && albumArtBackground.status === Image.Ready
            }

            ColorQuantizer {
                id: colorQuantizer
                source: albumArtBackground
                depth: 0
                rescaleSize: 1
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, albumArtBackground.status === Image.Ready ? 0.62 : 0.18)
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(immersiveWindow.artAccent.r, immersiveWindow.artAccent.g, immersiveWindow.artAccent.b, 0.13)
            }

            FocusScope {
                id: focusRoot
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.lyricsFullscreenOpen = false;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Space && root.player) {
                        root.player.togglePlaying();
                        event.accepted = true;
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Math.max(28, Math.min(parent.width, parent.height) * 0.055)
                    spacing: 24

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.large
                            color: "white"
                            text: "lyrics"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Now playing")
                            color: Qt.rgba(1, 1, 1, 0.82)
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                        }

                        ControlButton {
                            symbol: "close"
                            label: Translation.tr("Close immersive lyrics")
                            callback: () => GlobalStates.lyricsFullscreenOpen = false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 36

                        ColumnLayout {
                            Layout.preferredWidth: Math.min(parent.width * 0.35, 420)
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 20

                            Rectangle {
                                id: coverFrame
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: Math.min(420, immersiveWindow.height * 0.42, immersiveWindow.width * 0.28)
                                Layout.preferredHeight: Math.min(420, immersiveWindow.height * 0.42, immersiveWindow.width * 0.28)
                                radius: Appearance.rounding.large
                                color: Qt.rgba(1, 1, 1, 0.1)
                                clip: true

                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: coverFrame.width
                                        height: coverFrame.height
                                        radius: coverFrame.radius
                                    }
                                }

                                Image {
                                    id: coverImage
                                    anchors.fill: parent
                                    source: root.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 520
                                    sourceSize.height: 520
                                    asynchronous: true
                                    cache: false
                                    visible: status === Image.Ready
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: coverImage.status !== Image.Ready
                                    iconSize: 72
                                    color: Qt.rgba(1, 1, 1, 0.75)
                                    text: "music_note"
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                                color: "white"
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.DemiBold
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                Accessible.name: text
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.player?.trackArtist ?? ""
                                color: Qt.rgba(1, 1, 1, 0.72)
                                font.pixelSize: Appearance.font.pixelSize.large
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: `${StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)}  /  ${StringUtils.friendlyTimeForSeconds(root.player?.length ?? 0)}`
                                color: Qt.rgba(1, 1, 1, 0.68)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.features: { "tnum": 1 }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumWidth: 320
                            radius: Appearance.rounding.large
                            color: Qt.rgba(immersiveWindow.artAccent.r, immersiveWindow.artAccent.g, immersiveWindow.artAccent.b, 0.13)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.1)

                            Lyrics {
                                anchors.fill: parent
                                anchors.margins: 32
                                textAlignment: Text.AlignHCenter
                                textColor: Qt.rgba(1, 1, 1, 0.75)
                                activeColor: "white"
                                dimColor: Qt.rgba(1, 1, 1, 0.38)
                                vocalColor: Qt.rgba(1, 1, 1, 0.88)
                                fontScale: Math.max(1.25, Math.min(1.75, parent.height / 620))
                                lineSpacing: 12
                                animateTransitions: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        StyledText {
                            Layout.fillWidth: true
                            visible: Config.options.media.showRomanization && LyricsService.romanizationSupported && !LyricsService.romanizationAvailable
                            text: Translation.tr("Install ICU uconv for romanization")
                            color: Qt.rgba(1, 1, 1, 0.65)
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        ControlButton {
                            symbol: "skip_previous"
                            label: Translation.tr("Previous track")
                            callback: () => root.player?.previous()
                        }

                        ControlButton {
                            symbol: root.player?.isPlaying ? "pause" : "play_arrow"
                            label: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                            callback: () => root.player?.togglePlaying()
                        }

                        ControlButton {
                            symbol: "skip_next"
                            label: Translation.tr("Next track")
                            callback: () => root.player?.next()
                        }
                    }
                }
            }
        }
    }
}
