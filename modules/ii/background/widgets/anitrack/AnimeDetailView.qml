import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    signal backRequested()
    signal launchRequested(string title)
    property var anime: null

    ColumnLayout {
        anchors.fill: parent
        spacing: 9

        RippleButton {
            Layout.alignment: Qt.AlignLeft
            implicitWidth: 92
            implicitHeight: 34
            buttonRadius: Appearance.rounding.small
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Back to search results")
            onClicked: root.backRequested()
            contentItem: RowLayout {
                spacing: 5
                MaterialSymbol {
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    Accessible.ignored: true
                }
                StyledText {
                    text: qsTr("Results")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 146
            spacing: 12

            PosterThumbnail {
                Layout.preferredWidth: 100
                Layout.preferredHeight: 140
                sourceUrl: root.anime?.imageUrl || ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 5

                StyledText {
                    Layout.fillWidth: true
                    text: root.anime?.title || qsTr("Anime details")
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: [root.anime?.type || "", root.anime?.year || ""]
                        .filter(value => !!value).join("  ·  ")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const anime = root.anime || {};
                        const parts = [];
                        if (anime.episodes > 0)
                            parts.push(qsTr("%1 eps").arg(anime.episodes));
                        if (anime.score > 0)
                            parts.push(qsTr("★ %1").arg(anime.score.toFixed(1)));
                        return parts.join("  ·  ");
                    }
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.anime?.status || ""
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.anime?.genres?.length > 0 ? root.anime.genres.join("  ·  ") : ""
            visible: text !== ""
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Synopsis")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: synopsisText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            StyledText {
                id: synopsisText
                width: parent.width
                text: root.anime?.synopsis || qsTr("No synopsis is available for this title.")
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colPrimary
            enabled: !!root.anime?.title
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Search this title in ani-cli")
            onClicked: root.launchRequested(root.anime?.title || "")
            contentItem: RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: "play_arrow"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                    Accessible.ignored: true
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Search this title in ani-cli")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimary
                }
                MaterialSymbol {
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                    Accessible.ignored: true
                }
            }
        }
    }
}
