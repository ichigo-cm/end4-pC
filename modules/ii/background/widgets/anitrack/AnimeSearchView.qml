pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
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

    function imageUrl(anime) {
        const images = anime?.images || {};
        const webp = images.webp || {};
        const jpg = images.jpg || {};
        const candidate = String(webp.image_url || jpg.image_url || "");
        return /^https:\/\//i.test(candidate) ? candidate : "";
    }

    function normalizeAnime(item) {
        const aired = item?.aired || {};
        const fromDate = aired.from ? new Date(aired.from) : null;
        return {
            id: Number(item?.mal_id) || 0,
            title: String(item?.title_english || item?.title || item?.title_japanese || qsTr("Untitled anime")),
            nativeTitle: String(item?.title_japanese || ""),
            imageUrl: imageUrl(item),
            year: Number(item?.year) || (fromDate && !isNaN(fromDate.getTime()) ? fromDate.getFullYear() : 0),
            type: String(item?.type || ""),
            episodes: Number(item?.episodes) || 0,
            score: Number(item?.score) || 0,
            status: String(item?.status || ""),
            synopsis: String(item?.synopsis || ""),
            genres: Array.isArray(item?.genres) ? item.genres.map(genre => String(genre?.name || "")).filter(name => name !== "") : []
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
        scheduleSearch.interval = apiCoordinator ? apiCoordinator.jikanDelayMs() : 0;
        scheduleSearch.restart();
    }

    function loadMore() {
        if (!hasNextPage || loadingMore || activeRequest)
            return;
        queuedQuery = submittedQuery;
        queuedPage = currentPage + 1;
        queuedAppend = true;
        loadingMore = true;
        errorMessage = "";
        scheduleSearch.interval = apiCoordinator ? apiCoordinator.jikanDelayMs() : 0;
        scheduleSearch.restart();
    }

    function issueSearch(query, page, append) {
        if (!apiCoordinator || !apiCoordinator.claimJikanRequest()) {
            scheduleSearch.interval = Math.max(100, apiCoordinator ? apiCoordinator.jikanDelayMs() : 1200);
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
        request.open("GET", `https://api.jikan.moe/v4/anime?q=${encodeURIComponent(query)}&limit=12&page=${page}`);
        request.setRequestHeader("Accept", "application/json");
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || root.activeRequest !== request)
                return;
            root.activeRequest = null;
            requestTimeout.stop();
            if (request.status !== 200) {
                if (request.status === 429 && root.apiCoordinator)
                    root.apiCoordinator.noteJikanRateLimit(request.getResponseHeader("Retry-After"));
                root.errorMessage = request.status === 429
                    ? qsTr("Jikan is rate-limiting requests. Try again in a little while.")
                    : request.status === 0
                        ? qsTr("Could not reach Jikan. Check your connection and try again.")
                        : qsTr("Anime search failed (HTTP %1).").arg(request.status);
                root.loadingMore = false;
                if (!append || root.results.length === 0)
                    root.requestState = "error";
                return;
            }
            try {
                const response = JSON.parse(request.responseText);
                const items = Array.isArray(response.data) ? response.data : [];
                const normalized = items.map(item => root.normalizeAnime(item));
                root.results = append ? root.results.concat(normalized) : normalized;
                root.currentPage = page;
                root.hasNextPage = response.pagination?.has_next_page === true;
                root.loadingMore = false;
                root.requestState = root.results.length > 0 ? "ready" : "empty";
            } catch (error) {
                root.errorMessage = qsTr("Could not read anime search results.");
                root.loadingMore = false;
                if (!append || root.results.length === 0)
                    root.requestState = "error";
                console.warn("[AniTrackWidget] Could not parse Jikan search response:", error);
            }
        };
        request.send();
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
        interval: 12000
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
            spacing: 10

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
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    selectionColor: Appearance.colors.colPrimaryContainer
                    selectedTextColor: Appearance.colors.colOnPrimaryContainer
                    Accessible.name: qsTr("Search anime titles")
                    onAccepted: root.search()
                    background: Rectangle {
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: searchField.activeFocus ? 2 : 1
                        border.color: searchField.activeFocus
                            ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    }
                }
                RippleButton {
                    implicitWidth: 44
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.normal
                    enabled: root.requestState !== "loading"
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Search anime")
                    onClicked: root.search()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.requestState === "loading" ? "hourglass_top" : "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                        Accessible.ignored: true
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.requestState === "ready"
                    ? qsTr("Results for “%1”").arg(root.submittedQuery)
                    : root.requestState === "empty"
                        ? qsTr("No matches for “%1”").arg(root.submittedQuery)
                        : root.requestState === "idle" ? qsTr("Search to find your next watch") : ""
                visible: text !== ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.errorMessage !== "" && root.results.length > 0
                text: root.errorMessage
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledListView {
                    id: resultList
                    anchors.fill: parent
                    clip: true
                    spacing: 5
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
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: root.loadingMore ? qsTr("Loading more results") : qsTr("Load more results")
                            onClicked: root.loadMore()
                            contentItem: RowLayout {
                                spacing: 7
                                MaterialSymbol {
                                    text: root.loadingMore ? "hourglass_top" : "expand_more"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colPrimary
                                    Accessible.ignored: true
                                }
                                StyledText {
                                    text: root.loadingMore ? qsTr("Loading more…") : qsTr("Load more")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                    delegate: RippleButton {
                        id: resultButton
                        required property var modelData
                        width: resultList.width
                        height: 76
                        buttonRadius: Appearance.rounding.normal
                        colBackground: Appearance.colors.colLayer1
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Details for %1").arg(modelData.title)
                        onClicked: root.openDetails(modelData)
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 10
                            spacing: 10
                            PosterThumbnail {
                                Layout.preferredWidth: 43
                                Layout.preferredHeight: 60
                                Layout.alignment: Qt.AlignVCenter
                                sourceUrl: resultButton.modelData.imageUrl
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultButton.modelData.title
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: [resultButton.modelData.type, resultButton.modelData.year || ""]
                                        .filter(value => !!value).join("  ·  ")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultButton.modelData.score > 0
                                        ? qsTr("★ %1").arg(resultButton.modelData.score.toFixed(1))
                                        : qsTr("Score unavailable")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colSubtext
                                Accessible.ignored: true
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
                            ? Appearance.colors.colError : Appearance.colors.colPrimary
                        Accessible.ignored: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.requestState === "loading" || root.requestState === "waiting"
                            ? qsTr("Searching Jikan…")
                            : root.requestState === "error" ? qsTr("Search unavailable")
                            : root.requestState === "empty" ? qsTr("No anime found")
                            : qsTr("Find your next watch")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.requestState === "loading" || root.requestState === "waiting"
                            ? qsTr("Looking up titles and details.")
                            : root.requestState === "error" ? root.errorMessage
                            : root.requestState === "empty" ? qsTr("Try another title or spelling.")
                            : qsTr("Type a title above, then press Enter.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        AnimeDetailView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            anime: root.selectedAnime
            onBackRequested: root.closeDetails()
            onLaunchRequested: title => root.launchRequested(title)
        }
    }
}
