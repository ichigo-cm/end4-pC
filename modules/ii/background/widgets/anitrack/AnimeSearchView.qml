pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    signal launchRequested(string title)

    property var results: []
    property var activeRequest: null
    property var selectedAnime: null
    property string requestState: "idle"
    property string errorMessage: ""
    property string submittedQuery: ""
    property string queuedQuery: ""
    property int queuedPage: 1
    property int currentPage: 0
    property bool queuedAppend: false
    property bool hasNextPage: false
    property bool loadingMore: false
    property var apiCoordinator: null
    required property var palette

    function imageUrl(anime) {
        const cover = anime?.coverImage || {};
        const candidate = String(cover.extraLarge || cover.large || cover.medium || "");
        return /^https:\/\//i.test(candidate) ? candidate : "";
    }

    function normalizeAnime(item) {
        const title = item?.title || {};
        const date = item?.startDate || {};
        const averageScore = Number(item?.averageScore) || 0;
        const statusNames = ({
            FINISHED: qsTr("Finished"),
            RELEASING: qsTr("Currently Airing"),
            NOT_YET_RELEASED: qsTr("Not Yet Released"),
            CANCELLED: qsTr("Cancelled"),
            HIATUS: qsTr("On Hiatus")
        });
        return {
            id: Number(item?.id) || 0,
            title: String(title.english || title.romaji || title.native || qsTr("Untitled anime")),
            nativeTitle: String(title.native || ""),
            imageUrl: imageUrl(item),
            year: Number(item?.seasonYear) || Number(date.year) || 0,
            type: String(item?.format || "").replace(/_/g, " "),
            episodes: Number(item?.episodes) || 0,
            score: averageScore / 10,
            status: statusNames[item?.status] || String(item?.status || ""),
            synopsis: String(item?.description || ""),
            genres: Array.isArray(item?.genres) ? item.genres.map(genre => String(genre || "")).filter(name => name !== "") : []
        };
    }

    function search() {
        const query = searchField.text.trim();
        if (!query) {
            queuedQuery = "";
            hasNextPage = false;
            currentPage = 0;
            loadingMore = false;
            scheduleSearch.stop();
            if (activeRequest) {
                activeRequest.abort();
                activeRequest = null;
            }
            requestTimeout.stop();
            requestState = "idle";
            results = [];
            errorMessage = "";
            return;
        }
        if (activeRequest) {
            activeRequest.abort();
            activeRequest = null;
            requestTimeout.stop();
        }
        queuedQuery = query;
        queuedPage = 1;
        queuedAppend = false;
        hasNextPage = false;
        currentPage = 0;
        loadingMore = false;
        results = [];
        requestState = "waiting";
        scheduleSearch.interval = apiCoordinator ? apiCoordinator.aniListDelayMs() : 0;
        scheduleSearch.restart();
    }

    function refreshSearch() {
        const query = searchField.text.trim() || submittedQuery;
        if (!query)
            return;
        searchField.text = query;
        search();
    }

    function searchFromWeb(query) {
        searchField.text = String(query || "");
        search();
    }

    function loadMore() {
        if (!hasNextPage || loadingMore || activeRequest)
            return;
        queuedQuery = submittedQuery;
        queuedPage = currentPage + 1;
        queuedAppend = true;
        loadingMore = true;
        errorMessage = "";
        scheduleSearch.interval = apiCoordinator ? apiCoordinator.aniListDelayMs() : 0;
        scheduleSearch.restart();
    }

    function issueSearch(query, page, append) {
        if (!apiCoordinator || !apiCoordinator.claimAniListRequest()) {
            scheduleSearch.interval = Math.max(100, apiCoordinator ? apiCoordinator.aniListDelayMs() : 2200);
            scheduleSearch.restart();
            return;
        }
        const request = new XMLHttpRequest();
        activeRequest = request;
        submittedQuery = query;
        if (!append)
            results = [];
        errorMessage = "";
        if (!append)
            requestState = "loading";
        const graphQuery = `query ($search: String!, $page: Int!) {
            Page(page: $page, perPage: 12) {
                pageInfo { hasNextPage }
                media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
                    id title { romaji english native }
                    description(asHtml: false) averageScore episodes format status genres
                    coverImage { extraLarge large medium }
                    startDate { year } seasonYear
                }
            }
        }`;
        request.open("POST", "https://graphql.anilist.co");
        request.setRequestHeader("Accept", "application/json");
        request.setRequestHeader("Content-Type", "application/json");
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || root.activeRequest !== request)
                return;
            root.activeRequest = null;
            requestTimeout.stop();
            if (request.status !== 200) {
                if (request.status === 429 && root.apiCoordinator)
                    root.apiCoordinator.noteAniListRateLimit(request.getResponseHeader("Retry-After"));
                root.errorMessage = request.status === 429
                    ? qsTr("AniList is rate-limiting requests. Try again in a little while.")
                    : request.status === 0
                        ? qsTr("Could not reach AniList. Check your connection and try again.")
                        : qsTr("Anime search failed (HTTP %1).").arg(request.status);
                root.loadingMore = false;
                if (!append || root.results.length === 0)
                    root.requestState = "error";
                return;
            }
            try {
                const response = JSON.parse(request.responseText);
                if (response.errors?.length)
                    throw new Error(String(response.errors[0]?.message || "AniList returned an error."));
                const pageData = response?.data?.Page || {};
                const items = Array.isArray(pageData.media) ? pageData.media : [];
                const normalized = items.map(item => root.normalizeAnime(item));
                root.results = append ? root.results.concat(normalized) : normalized;
                root.currentPage = page;
                root.hasNextPage = pageData.pageInfo?.hasNextPage === true;
                root.loadingMore = false;
                root.requestState = root.results.length > 0 ? "ready" : "empty";
            } catch (error) {
                root.errorMessage = qsTr("Could not read anime search results.");
                root.loadingMore = false;
                if (!append || root.results.length === 0)
                    root.requestState = "error";
                console.warn("[AniTrackWidget] Could not parse AniList search response:", error);
            }
        };
        request.send(JSON.stringify({query: graphQuery, variables: {search: query, page: page}}));
        requestTimeout.restart();
    }

    function openDetails(anime) {
        selectedAnime = anime;
    }

    function closeDetails() {
        selectedAnime = null;
    }

    Component.onDestruction: {
        scheduleSearch.stop();
        requestTimeout.stop();
        if (activeRequest) {
            const request = activeRequest;
            activeRequest = null;
            request.abort();
        }
    }

    Timer {
        id: scheduleSearch
        interval: 0
        repeat: false
        onTriggered: {
            if (root.queuedQuery)
                root.issueSearch(root.queuedQuery, root.queuedPage, root.queuedAppend);
        }
    }

    Timer {
        id: requestTimeout
        interval: 20000
        repeat: false
        onTriggered: {
            if (!root.activeRequest)
                return;
            const request = root.activeRequest;
            root.activeRequest = null;
            request.abort();
            root.errorMessage = qsTr("Anime search timed out. Try again.");
            const hadResults = root.results.length > 0;
            root.loadingMore = false;
            if (!hadResults)
                root.requestState = "error";
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: root.selectedAnime ? 1 : 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    placeholderText: qsTr("Search anime titles")
                    selectByMouse: true
                    activeFocusOnTab: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.palette.text
                    placeholderTextColor: root.palette.muted
                    selectionColor: root.palette.lavender
                    selectedTextColor: root.palette.buttonText
                    Accessible.name: qsTr("Search anime titles")
                    onAccepted: root.search()
                    onActiveFocusChanged: {
                        if (activeFocus)
                            GlobalStates.desktopWidgetKeyboardFocus = true;
                    }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                            searchField.forceActiveFocus();
                            GlobalStates.desktopWidgetKeyboardFocus = true;
                        }
                    }
                    background: Rectangle {
                        radius: 13
                        color: root.palette.panel
                        border.width: searchField.activeFocus ? 2 : 1
                        border.color: searchField.activeFocus
                            ? root.palette.lavender : root.palette.outline
                    }
                }
                RippleButton {
                    implicitWidth: 44
                    implicitHeight: 44
                    buttonRadius: 13
                    enabled: root.requestState !== "loading"
                    activeFocusOnTab: true
                    border: true
                    borderWidth: 2
                    colBorder: activeFocus ? root.palette.mint : root.palette.outline
                    colBackground: root.palette.surface
                    colBackgroundHover: root.palette.cardHover
                    colRipple: root.palette.lavender
                    rippleEnabled: !Config.options.appearance.reducedMotion
                    rippleDuration: 140
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Search anime")
                    onClicked: root.search()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.requestState === "loading" ? "hourglass_top" : "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.palette.lavender
                        Accessible.ignored: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.requestState === "ready" || root.requestState === "empty"
                StyledText {
                    Layout.fillWidth: true
                    text: root.requestState === "ready"
                        ? qsTr("Results for “%1”").arg(root.submittedQuery)
                        : qsTr("No matches for “%1”").arg(root.submittedQuery)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root.palette.secondary
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.errorMessage !== "" && root.results.length > 0
                text: root.errorMessage
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.palette.error
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledListView {
                    id: resultList
                    anchors.fill: parent
                    clip: true
                    spacing: 9
                    animateAppearance: false
                    model: root.results
                    visible: root.requestState === "ready" && root.results.length > 0
                    footer: Component {
                        RippleButton {
                            width: resultList.width
                            height: 40
                            visible: root.hasNextPage
                            enabled: !root.loadingMore
                            buttonRadius: Appearance.rounding.normal
                            border: true
                            borderWidth: 2
                            colBorder: activeFocus ? root.palette.mint : "transparent"
                            colBackground: root.palette.surface
                            colBackgroundHover: root.palette.cardHover
                            colRipple: root.palette.lavender
                            rippleEnabled: !Config.options.appearance.reducedMotion
                            rippleDuration: 140
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: root.loadingMore ? qsTr("Loading more results") : qsTr("Load more results")
                            onClicked: root.loadMore()
                            contentItem: RowLayout {
                                spacing: 7
                                MaterialSymbol {
                                    text: root.loadingMore ? "hourglass_top" : "expand_more"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: root.palette.lavender
                                    Accessible.ignored: true
                                }
                                StyledText {
                                    text: root.loadingMore ? qsTr("Loading more…") : qsTr("Load more")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: root.palette.lavender
                                }
                            }
                        }
                    }
                    delegate: Item {
                        id: resultCard
                        required property var modelData
                        required property int index
                        width: resultList.width
                        height: index === 0 ? 164 : 120

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: resultCard.index === 0 ? root.palette.surface : root.palette.card
                            border.width: 1
                            border.color: root.palette.outline
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            PosterThumbnail {
                                Layout.preferredWidth: resultCard.index === 0 ? 92 : 66
                                Layout.preferredHeight: resultCard.index === 0 ? 142 : 98
                                sourceUrl: resultCard.modelData.imageUrl
                                palette: root.palette
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 3

                                StyledText {
                                    visible: resultCard.index === 0
                                    text: qsTr("TOP MATCH")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: root.palette.mint
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultCard.modelData.title
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: resultCard.index === 0
                                        ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: root.palette.text
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: [resultCard.modelData.type,
                                        resultCard.modelData.year || "",
                                        resultCard.modelData.episodes > 0
                                            ? qsTr("%1 eps").arg(resultCard.modelData.episodes) : ""]
                                        .filter(value => !!value).join("  ·  ")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.palette.secondary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultCard.modelData.score > 0
                                        ? qsTr("★ %1").arg(resultCard.modelData.score.toFixed(1))
                                        : resultCard.modelData.status || qsTr("Score unavailable")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.palette.mint
                                }

                                Item { Layout.fillHeight: true }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RippleButton {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        buttonRadius: 10
                                        colBackground: root.palette.lavender
                                        colBackgroundHover: root.palette.primaryHover
                                        colRipple: root.palette.text
                                        rippleEnabled: !Config.options.appearance.reducedMotion
                                        rippleDuration: 140
                                        border: true
                                        borderWidth: 2
                                        colBorder: activeFocus ? root.palette.mint : "transparent"
                                        activeFocusOnTab: true
                                        Accessible.role: Accessible.Button
                                        Accessible.name: qsTr("Open %1 in ani-cli").arg(resultCard.modelData.title)
                                        onClicked: root.launchRequested(resultCard.modelData.title)
                                        contentItem: StyledText {
                                            text: qsTr("Open in ani-cli")
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: root.palette.buttonText
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 68
                                        Layout.preferredHeight: 34
                                        buttonRadius: 10
                                        border: true
                                        borderWidth: 2
                                        colBorder: activeFocus ? root.palette.mint : root.palette.outline
                                        colBackground: root.palette.card
                                        colBackgroundHover: root.palette.cardHover
                                        colRipple: root.palette.lavender
                                        rippleEnabled: !Config.options.appearance.reducedMotion
                                        rippleDuration: 140
                                        activeFocusOnTab: true
                                        Accessible.role: Accessible.Button
                                        Accessible.name: qsTr("View details for %1").arg(resultCard.modelData.title)
                                        onClicked: root.openDetails(resultCard.modelData)
                                        contentItem: StyledText {
                                            text: qsTr("Details")
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Medium
                                            color: root.palette.secondary
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 8
                    visible: !resultList.visible
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.requestState === "loading" || root.requestState === "waiting"
                            ? "hourglass_top" : root.requestState === "error" ? "error_outline"
                            : root.requestState === "empty" ? "search_off" : "travel_explore"
                        iconSize: 30
                        color: root.requestState === "error"
                            ? root.palette.error : root.palette.lavender
                        Accessible.ignored: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.requestState === "loading" || root.requestState === "waiting"
                            ? qsTr("Searching AniList…")
                            : root.requestState === "error" ? qsTr("Search unavailable")
                            : root.requestState === "empty" ? qsTr("No anime found")
                            : qsTr("Search anime on AniList")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: root.palette.text
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.requestState === "loading" || root.requestState === "waiting"
                            ? qsTr("Looking up titles and details.")
                            : root.requestState === "error" ? root.errorMessage
                            : root.requestState === "empty" ? qsTr("Try another title or spelling.")
                            : qsTr("Enter a title above to see live matches and episode details.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.palette.secondary
                    }
                }
            }
        }

        AnimeDetailView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            anime: root.selectedAnime
            palette: root.palette
            onBackRequested: root.closeDetails()
            onLaunchRequested: title => root.launchRequested(title)
        }
    }
}
