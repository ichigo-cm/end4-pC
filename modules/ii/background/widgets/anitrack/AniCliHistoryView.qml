pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    signal refreshRequested()
    signal continueRequested()
    signal titleRequested(string title)
    property var entries: []
    property string stateName: "loading"
    property string errorMessage: ""
    property bool refreshing: false
    property var apiCoordinator: null
    property var artworkCache: ({})
    property var artworkQueue: []
    property var artworkRequest: null
    property string activeArtworkKey: ""

    function normalizedTitle(value) {
        return String(value || "").normalize("NFKC").toLowerCase()
            .replace(/[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+/g, " ").trim();
    }

    function artworkFor(title) {
        return artworkCache[normalizedTitle(title)]?.imageUrl || "";
    }

    function queueArtworkMatches() {
        const cache = artworkCache;
        const queued = [];
        const seen = {};
        for (let index = 0; index < Math.min(entries.length, 12); index++) {
            const entry = entries[index];
            const key = normalizedTitle(entry?.title);
            const cached = cache[key];
            const failedRecently = cached?.failedAt && Date.now() - cached.failedAt < 300000;
            if (!key || cached?.imageUrl || failedRecently || seen[key])
                continue;
            seen[key] = true;
            queued.push({key: key, title: String(entry.title)});
        }
        artworkQueue = queued;
        scheduleArtworkMatch();
    }

    function scheduleArtworkMatch() {
        if (!visible || artworkRequest || artworkQueue.length === 0)
            return;
        artworkTimer.interval = Math.max(0, apiCoordinator ? apiCoordinator.aniListDelayMs() : 2200);
        artworkTimer.restart();
    }

    function fetchNextArtworkMatch() {
        if (!visible || artworkRequest || artworkQueue.length === 0)
            return;
        if (!apiCoordinator || !apiCoordinator.claimAniListRequest()) {
            artworkTimer.interval = Math.max(100, apiCoordinator ? apiCoordinator.aniListDelayMs() : 2200);
            artworkTimer.restart();
            return;
        }
        const current = artworkQueue[0];
        const request = new XMLHttpRequest();
        artworkRequest = request;
        activeArtworkKey = current.key;
        const graphQuery = `query ($search: String!) {
            Page(page: 1, perPage: 10) {
                media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
                    title { romaji english native }
                    coverImage { extraLarge large medium }
                }
            }
        }`;
        request.open("POST", "https://graphql.anilist.co");
        request.setRequestHeader("Accept", "application/json");
        request.setRequestHeader("Content-Type", "application/json");
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || root.artworkRequest !== request)
                return;
            root.artworkRequest = null;
            root.activeArtworkKey = "";
            artworkTimeout.stop();
            if (request.status === 429) {
                if (root.apiCoordinator)
                    root.apiCoordinator.noteAniListRateLimit(request.getResponseHeader("Retry-After"));
                root.scheduleArtworkMatch();
                return;
            }
            let matchedImage = "";
            if (request.status === 200) {
                try {
                    const response = JSON.parse(request.responseText);
                    if (response.errors?.length)
                        throw new Error(String(response.errors[0]?.message || "AniList returned an error."));
                    const results = Array.isArray(response?.data?.Page?.media) ? response.data.Page.media : [];
                    const target = current.key;
                    const exact = results.find(item => {
                        const title = item?.title || {};
                        const titles = [title.romaji, title.english, title.native];
                        return titles.some(title => root.normalizedTitle(title) === target);
                    });
                    if (exact) {
                        const cover = exact.coverImage || {};
                        const candidate = String(cover.extraLarge || cover.large || cover.medium || "");
                        if (/^https:\/\//i.test(candidate))
                            matchedImage = candidate;
                    }
                } catch (error) {
                    console.warn("[AniTrackWidget] Could not parse history artwork response:", error);
                }
            }
            if (request.status === 200) {
                const nextCache = Object.assign({}, root.artworkCache);
                nextCache[current.key] = {
                    imageUrl: matchedImage,
                    failedAt: matchedImage ? 0 : Date.now()
                };
                root.artworkCache = nextCache;
            } else if (request.status !== 429) {
                const nextCache = Object.assign({}, root.artworkCache);
                nextCache[current.key] = {imageUrl: "", failedAt: Date.now()};
                root.artworkCache = nextCache;
            }
            root.artworkQueue = root.artworkQueue.filter(item => item.key !== current.key);
            root.scheduleArtworkMatch();
        };
        request.send(JSON.stringify({query: graphQuery, variables: {search: current.title}}));
        artworkTimeout.restart();
    }

    onEntriesChanged: queueArtworkMatches()
    onVisibleChanged: {
        if (visible)
            scheduleArtworkMatch();
        else
            artworkTimer.stop();
    }
    Component.onDestruction: {
        artworkTimer.stop();
        artworkTimeout.stop();
        if (artworkRequest) {
            const request = artworkRequest;
            artworkRequest = null;
            request.abort();
        }
    }

    Timer {
        id: artworkTimer
        interval: 2200
        repeat: false
        onTriggered: root.fetchNextArtworkMatch()
    }

    Timer {
        id: artworkTimeout
        interval: 20000
        repeat: false
        onTriggered: {
            if (!root.artworkRequest)
                return;
            const request = root.artworkRequest;
            root.artworkRequest = null;
            const failedKey = root.activeArtworkKey;
            root.activeArtworkKey = "";
            request.abort();
            const nextCache = Object.assign({}, root.artworkCache);
            nextCache[failedKey] = {imageUrl: "", failedAt: Date.now()};
            root.artworkCache = nextCache;
            root.artworkQueue = root.artworkQueue.filter(item => item.key !== failedKey);
            root.scheduleArtworkMatch();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: qsTr("Saved episodes")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: qsTr("Read from ani-cli's local history")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    visible: root.refreshing && root.stateName === "ready"
                    text: qsTr("Updating…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
            }

            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Refresh ani-cli history")
                onClicked: root.refreshRequested()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    Accessible.ignored: true
                }
            }
        }

        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colPrimaryContainer
            enabled: root.stateName === "ready"
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Continue from ani-cli history")
            onClicked: root.continueRequested()
            contentItem: RowLayout {
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                MaterialSymbol {
                    text: "play_arrow"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnPrimaryContainer
                    Accessible.ignored: true
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Continue from history")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimaryContainer
                }
                MaterialSymbol {
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                    Accessible.ignored: true
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: historyList
                anchors.fill: parent
                clip: true
                spacing: 5
                animateAppearance: false
                model: root.entries
                visible: root.stateName === "ready" && root.entries.length > 0

                delegate: Item {
                    id: historyRow
                    required property var modelData
                    width: historyList.width
                    height: 66

                    RowLayout {
                        anchors.fill: parent
                        spacing: 9

                        PosterThumbnail {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 56
                            Layout.alignment: Qt.AlignVCenter
                            sourceUrl: root.artworkFor(historyRow.modelData.title)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                text: historyRow.modelData.title || qsTr("Untitled anime")
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("Episode %1 saved by ani-cli").arg(historyRow.modelData.episode || "—")
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.small
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Search %1 in ani-cli").arg(historyRow.modelData.title)
                            onClicked: root.titleRequested(historyRow.modelData.title)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "search"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                                Accessible.ignored: true
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 8
                visible: !historyList.visible

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.stateName === "loading" ? "hourglass_top"
                        : root.stateName === "error" ? "error_outline"
                        : "history"
                    iconSize: 30
                    color: root.stateName === "error"
                        ? Appearance.colors.colError : Appearance.colors.colPrimary
                    Accessible.ignored: true
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.stateName === "loading" ? qsTr("Reading ani-cli history…")
                        : root.stateName === "missing" ? qsTr("No ani-cli history yet")
                        : root.stateName === "error" ? qsTr("History unavailable")
                        : qsTr("Nothing saved yet")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.stateName === "loading" ? qsTr("Reading the local ani-cli state file.")
                        : root.stateName === "missing" ? qsTr("Watch an episode with ani-cli and its saved history will appear here.")
                        : root.stateName === "error" ? root.errorMessage
                        : qsTr("ani-cli has not saved any episode entries yet.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.stateName === "ready" && root.errorMessage !== ""
            text: root.errorMessage
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }
    }
}
