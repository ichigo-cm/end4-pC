pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root

    property real cardLength:    DockStyle.vertical ? mediaGrid.implicitHeight + Appearance.sizes.hyprlandGapsOut * 2 : DockStyle.mediaLength
    property real buttonPadding: 5
    property real artMargin:     5

    property var player: MprisController.activePlayer

    property var    artUrl:      player?.trackArtUrl ?? ""
    property string trackTitle:  player?.trackTitle  ?? ""
    property string trackArtist: player?.trackArtist ?? ""
    property bool   isPlaying:   player?.isPlaying   ?? false
    property bool   hasTrack:    trackTitle.length > 0

    property string artDownloadLocation: Directories.coverArt
    property string artFileName:         Qt.md5(artUrl)
    property string artFilePath:         `${artDownloadLocation}/${artFileName}`
    property bool   artDownloaded:       Boolean(root.artUrl && (root.artUrl.startsWith("data:") || root.artUrl.startsWith("file:/") || root.artUrl.startsWith("/")))

    property string displayedArtFilePath: {
        if (!root.artUrl || root.artUrl.length === 0) return ""
        if (root.artUrl.startsWith("data:")) return root.artUrl
        if (root.artUrl.startsWith("file:/")) return root.artUrl
        if (root.artUrl.startsWith("/")) return "file://" + root.artUrl
        if (!root.artDownloaded) return ""
        return Qt.resolvedUrl(artFilePath)
    }

    property color artDominantColor: ColorUtils.mix(
        colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary,
        Appearance.colors.colPrimaryContainer,
        0.8)

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    property int artRequestVersion: 0

    onArtFilePathChanged: requestArtDownload()
    function requestArtDownload() {
        root.artRequestVersion += 1
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            root.artDownloaded = false
            return
        }

        if (root.artUrl.startsWith("data:") || root.artUrl.startsWith("file:/") || root.artUrl.startsWith("/")) {
            root.artDownloaded = true
            return
        }

        if (root.artUrl.startsWith("http://") || root.artUrl.startsWith("https://")) {
            root.artDownloaded = false
            if (artDownloader.running) return
            artDownloader.targetFile  = root.artUrl
            artDownloader.artFilePath = root.artFilePath
            artDownloader.requestVersion = root.artRequestVersion
            artDownloader.running = true
        } else {
            root.artDownloaded = false
        }
    }

    Process {
        id: artDownloader
        property string targetFile:  root.artUrl
        property string artFilePath: root.artFilePath
        property int requestVersion: 0
        command: ["bash", "-c", `
            if [ -f "$1" ]; then exit 0; fi
            tmp=$(mktemp -- "$1.part.XXXXXX") || exit 1
            if curl --fail --location --silent --show-error --connect-timeout 5 --max-time 20 --max-filesize 10485760 --proto "=http,https" --proto-redir "=http,https" -o "$tmp" -- "$2" &&
                mv -f -- "$tmp" "$1"; then
                :
            else
                rm -f -- "$tmp"
                exit 1
            fi
        `, "_", artFilePath, targetFile]
        onExited: (exitCode, exitStatus) => {
            if (requestVersion !== root.artRequestVersion || targetFile !== root.artUrl || artFilePath !== root.artFilePath) {
                Qt.callLater(() => root.requestArtDownload())
                return
            }
            root.artDownloaded = exitCode === 0
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    visible:        root.hasTrack
    implicitWidth:  DockStyle.vertical ? (parent?.width ?? 46) : (root.hasTrack ? root.cardLength : 0)
    implicitHeight: DockStyle.vertical ? (root.hasTrack ? root.cardLength : 0) : (parent?.height ?? 46)

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: card
        visible: root.hasTrack
    }

    Rectangle {
        id: card
        anchors.fill:         parent
        anchors.topMargin:    Appearance.sizes.hyprlandGapsOut
        anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
        anchors.leftMargin:   Appearance.sizes.hyprlandGapsOut
        anchors.rightMargin:  Appearance.sizes.hyprlandGapsOut - (DockStyle.vertical ? 0 : 2)
        radius: Appearance.rounding.normal
        color:  "transparent"

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width:  card.width
                height: card.height
                radius: card.radius
            }
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
            z: 0
        }

        // Blur art 
        AnimatedImage {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true
            z: 1
            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }
        }

        // Overlay
        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.3)
            z: 2
        }

        GridLayout {
            id: mediaGrid
            width:  card.width
            height: card.height
            clip:   true
            columns: DockStyle.vertical ? 1 : -1
            rowSpacing: 8
            columnSpacing: 8
            z: 3

            // Art
            Rectangle {
                id: artRect
                Layout.alignment:  DockStyle.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                Layout.leftMargin: DockStyle.vertical ? 0 : root.artMargin + 2
                Layout.topMargin:  DockStyle.vertical ? root.artMargin + 2 : 0
                implicitWidth:     36
                implicitHeight:    36
                color:  ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)
                radius: Appearance.rounding.small

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width:  artRect.width
                        height: artRect.height
                        radius: artRect.radius
                    }
                }

                AnimatedImage {
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    sourceSize.width:  artRect.width
                    sourceSize.height: artRect.height
                }
            }

            // Artist + Title
            ColumnLayout {
                visible: !DockStyle.vertical
                Layout.fillWidth:  true
                Layout.fillHeight: true
                spacing: -2

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    font.pixelSize: Appearance.font.pixelSize.small - 2
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.trackTitle) || "Untitled"
                    font.pixelSize: Appearance.font.pixelSize.normal - 4
                    color: root.blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    opacity: 0.7
                }

                Item { Layout.fillHeight: true }
            }

            // Buttons
            GridLayout {
                Layout.rightMargin:  DockStyle.vertical ? 0 : 4
                Layout.alignment:    DockStyle.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                Layout.bottomMargin: DockStyle.vertical ? 4 : 0
                columns: DockStyle.vertical ? 1 : -1
                rowSpacing: 3
                columnSpacing: 3

                // Play / Pause
                RippleButton {
                    implicitWidth:  26
                    implicitHeight: 26
                    buttonRadius: root.isPlaying
                        ? Appearance.rounding.normal
                        : implicitWidth / 2
                    colBackground: root.isPlaying
                        ? root.blendedColors.colPrimary
                        : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.isPlaying
                        ? root.blendedColors.colPrimaryHover
                        : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.isPlaying
                        ? root.blendedColors.colPrimaryActive
                        : root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.togglePlaying()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.isPlaying
                            ? root.blendedColors.colOnPrimary
                            : root.blendedColors.colOnSecondaryContainer
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                // Next
                RippleButton {
                    implicitWidth:  28
                    implicitHeight: 28
                    colBackground:      ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
                    colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                    colRipple:          root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.next()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.blendedColors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
