import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    signal backRequested()
    signal launchRequested(string title)
    property var anime: null
    property var palette: ({
        panel: "#1A1928", surface: "#242235", card: "#211F30",
        cardHover: "#302B42", outline: "#655C77", text: "#F5F1FB",
        secondary: "#C7BEDA", muted: "#B9AFCA", lavender: "#C2AAFF",
        mint: "#9DE3D4", buttonText: "#20172F"
    })

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 178

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: root.palette.card
                border.width: 1
                border.color: root.palette.outline
                clip: true

                Image {
                    id: heroArtwork
                    anchors.fill: parent
                    source: root.anime?.imageUrl || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: Math.max(500, parent.width * 2)
                    sourceSize.height: Math.max(320, parent.height * 2)
                    opacity: status === Image.Ready ? 0.72 : 0
                    Accessible.ignored: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "movie"
                    iconSize: 44
                    color: root.palette.muted
                    visible: heroArtwork.status !== Image.Ready
                    Accessible.ignored: true
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "#3311101B" }
                        GradientStop { position: 0.42; color: "#8011101B" }
                        GradientStop { position: 1.0; color: "#F211101B" }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 5

                    RippleButton {
                        implicitWidth: 82
                        implicitHeight: 32
                        buttonRadius: 10
                        border: true
                        borderWidth: 2
                        colBorder: activeFocus ? root.palette.mint : root.palette.outline
                        colBackground: root.palette.panel
                        colBackgroundHover: root.palette.cardHover
                        colRipple: root.palette.lavender
                        rippleEnabled: !Config.options.appearance.reducedMotion
                        rippleDuration: 140
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Back to search results")
                        onClicked: root.backRequested()
                        contentItem: RowLayout {
                            spacing: 5
                            MaterialSymbol {
                                text: "arrow_back"
                                iconSize: Appearance.font.pixelSize.small
                                color: root.palette.text
                                Accessible.ignored: true
                            }
                            StyledText {
                                text: qsTr("Results")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: root.palette.text
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.fillWidth: true
                        text: [root.anime?.type || "",
                            root.anime?.year ? String(root.anime.year) : "",
                            root.anime?.status || ""]
                            .filter(value => !!value).join("  ·  ")
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: root.palette.mint
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.anime?.title || qsTr("Anime details")
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: root.palette.text
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const anime = root.anime || {};
                            const parts = [];
                            if (anime.episodes > 0)
                                parts.push(qsTr("%1 episodes").arg(anime.episodes));
                            if (anime.score > 0)
                                parts.push(qsTr("★ %1 / 10").arg(anime.score.toFixed(1)));
                            return parts.join("  ·  ");
                        }
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: root.palette.secondary
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.anime?.genres?.length > 0 ? root.anime.genres.join("  ·  ") : qsTr("Anime details from AniList")
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.palette.secondary
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Synopsis")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: root.palette.text
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: synopsisText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Accessible.name: qsTr("Anime synopsis")
            StyledText {
                id: synopsisText
                width: parent.width
                text: root.anime?.synopsis || qsTr("No synopsis is available for this title.")
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.palette.secondary
            }
        }

        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            buttonRadius: 12
            colBackground: root.palette.lavender
            colBackgroundHover: "#D2C1FF"
            colRipple: root.palette.text
            rippleEnabled: !Config.options.appearance.reducedMotion
            rippleDuration: 140
            border: true
            borderWidth: 2
            colBorder: activeFocus ? root.palette.mint : "transparent"
            enabled: !!root.anime?.title
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Search %1 in ani-cli").arg(root.anime?.title || "")
            onClicked: root.launchRequested(root.anime?.title || "")
            contentItem: RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: "play_arrow"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.palette.buttonText
                    Accessible.ignored: true
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Open in ani-cli")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.palette.buttonText
                }
                MaterialSymbol {
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.palette.buttonText
                    Accessible.ignored: true
                }
            }
        }
    }
}
