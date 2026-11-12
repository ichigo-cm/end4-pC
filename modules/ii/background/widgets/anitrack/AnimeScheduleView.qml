pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    signal launchRequested(string title)

    property var apiCoordinator: null
    property var entries: []
    property var activeRequest: null
    property string selectedDay: currentWeekday()
    property string stateName: "idle"
    property string errorMessage: ""
    property string queuedDay: ""
    property int queuedPage: 1
    property int currentPage: 0
    property bool queuedAppend: false
    property bool hasNextPage: false
    property bool loadingMore: false
    required property var palette

    readonly property var weekdays: [
        {key: "monday", name: qsTr("Monday"), shortName: qsTr("Mon")},
        {key: "tuesday", name: qsTr("Tuesday"), shortName: qsTr("Tue")},
        {key: "wednesday", name: qsTr("Wednesday"), shortName: qsTr("Wed")},
        {key: "thursday", name: qsTr("Thursday"), shortName: qsTr("Thu")},
        {key: "friday", name: qsTr("Friday"), shortName: qsTr("Fri")},
        {key: "saturday", name: qsTr("Saturday"), shortName: qsTr("Sat")},
        {key: "sunday", name: qsTr("Sunday"), shortName: qsTr("Sun")}
    ]

    function currentWeekday() {
        return ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][new Date().getDay()];
    }

    function dayLabel(day) {
        const found = weekdays.find(item => item.key === day);
        return found ? found.name : qsTr("Schedule");
    }

    function dayRange(day) {
        const targetDay = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"].indexOf(day);
        const now = new Date();
        const offset = (targetDay - now.getDay() + 7) % 7;
        const selectedDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
        const nextDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + 1);
        const fromDate = offset === 0 ? now : selectedDate;
        return {
            from: Math.floor(fromDate.getTime() / 1000),
            to: Math.floor(nextDate.getTime() / 1000)
        };
    }

    function imageUrl(anime) {
        const cover = anime?.coverImage || {};
        const candidate = String(cover.extraLarge || cover.large || cover.medium || "");
        return /^https:\/\//i.test(candidate) ? candidate : "";
    }

    function normalizeAnime(item) {
        const anime = item?.media || {};
        const title = anime.title || {};
        const timestamp = Number(item?.airingAt) * 1000;
        const airingDate = new Date(timestamp);
        const time = Number.isFinite(timestamp) && !isNaN(airingDate.getTime())
            ? airingDate.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"})
            : qsTr("Time not listed");
        const episode = Number(item?.episode) || 0;
        const averageScore = Number(anime.averageScore) || 0;

        return {
            id: Number(anime.id) || 0,
            title: String(title.english || title.romaji || title.native || qsTr("Untitled anime")),
            nativeTitle: String(title.native || ""),
            imageUrl: imageUrl(anime),
            type: String(anime.format || "").replace(/_/g, " "),
            broadcastTime: episode > 0 ? qsTr("%1 · Episode %2").arg(time).arg(episode) : time,
            score: averageScore / 10
        };
    }

    function loadSelectedDay() {
        if (stateName !== "idle" || activeRequest || scheduleRequest.running)
            return;
        requestPage(selectedDay, 1, false);
    }

    function selectDay(day) {
        if (day === selectedDay)
            return;
        selectedDay = day;
        entries = [];
        currentPage = 0;
        hasNextPage = false;
        errorMessage = "";
        loadingMore = false;
        requestPage(day, 1, false);
    }

    function refreshSelectedDay() {
        entries = [];
        currentPage = 0;
        hasNextPage = false;
        errorMessage = "";
        loadingMore = false;
        requestPage(selectedDay, 1, false);
    }

    function loadMore() {
        if (!hasNextPage || loadingMore || activeRequest || scheduleRequest.running)
            return;
        requestPage(selectedDay, currentPage + 1, true);
    }

    function retry() {
        const page = queuedAppend ? queuedPage : 1;
        requestPage(selectedDay, page, queuedAppend);
    }

    function requestPage(day, page, append) {
        scheduleRequest.stop();
        requestTimeout.stop();
        if (activeRequest) {
            const oldRequest = activeRequest;
            activeRequest = null;
            oldRequest.abort();
        }
        queuedDay = day;
        queuedPage = page;
        queuedAppend = append;
        errorMessage = "";
        if (append)
            loadingMore = true;
        else if (entries.length === 0)
            stateName = "waiting";
        scheduleRequest.interval = Math.max(0, apiCoordinator ? apiCoordinator.aniListDelayMs() : 0);
        scheduleRequest.restart();
    }

    function issueScheduleRequest() {
        if (!apiCoordinator || !apiCoordinator.claimAniListRequest()) {
            scheduleRequest.interval = Math.max(100, apiCoordinator ? apiCoordinator.aniListDelayMs() : 2200);
            scheduleRequest.restart();
            return;
        }

        const day = queuedDay;
        const page = queuedPage;
        const append = queuedAppend;
        const request = new XMLHttpRequest();
        activeRequest = request;
        if (!append && entries.length === 0)
            stateName = "loading";

        const range = root.dayRange(day);
        const graphQuery = `query ($page: Int!, $from: Int!, $to: Int!) {
            Page(page: $page, perPage: 25) {
                pageInfo { hasNextPage }
                airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, notYetAired: true, sort: TIME) {
                    id airingAt episode
                    media {
                        id title { romaji english native }
                        averageScore episodes format status genres
                        coverImage { extraLarge large medium }
                    }
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
                    ? qsTr("AniList is rate-limiting requests. Wait a little, then retry.")
                    : request.status === 0
                        ? qsTr("Could not reach AniList. Check your connection and try again.")
                        : qsTr("Weekly schedule failed (HTTP %1). Retry to try again.").arg(request.status);
                root.loadingMore = false;
                root.stateName = root.entries.length > 0 ? "ready" : "error";
                return;
            }

            try {
                const response = JSON.parse(request.responseText);
                if (response.errors?.length)
                    throw new Error(String(response.errors[0]?.message || "AniList returned an error."));
                const pageData = response?.data?.Page || {};
                const items = Array.isArray(pageData.airingSchedules) ? pageData.airingSchedules : [];
                const normalized = items.map(item => root.normalizeAnime(item));
                root.entries = append ? root.entries.concat(normalized) : normalized;
                root.currentPage = page;
                root.hasNextPage = pageData.pageInfo?.hasNextPage === true;
                root.loadingMore = false;
                root.errorMessage = "";
                root.stateName = root.entries.length > 0 ? "ready" : "empty";
            } catch (error) {
                root.errorMessage = qsTr("Could not read this day's schedule. Retry to try again.");
                root.loadingMore = false;
                root.stateName = root.entries.length > 0 ? "ready" : "error";
                console.warn("[AniTrackWidget] Could not parse AniList schedule response:", error);
            }
        };
        request.send(JSON.stringify({query: graphQuery, variables: {page: page, from: range.from, to: range.to}}));
        requestTimeout.restart();
    }

    Component.onDestruction: {
        scheduleRequest.stop();
        requestTimeout.stop();
        if (activeRequest) {
            const request = activeRequest;
            activeRequest = null;
            request.abort();
        }
    }

    Timer {
        id: scheduleRequest
        interval: 0
        repeat: false
        onTriggered: root.issueScheduleRequest()
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
            root.errorMessage = qsTr("The schedule request timed out. Retry to try again.");
            root.loadingMore = false;
            root.stateName = root.entries.length > 0 ? "ready" : "error";
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: root.dayLabel(root.selectedDay)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: root.palette.text
            }

            StyledText {
                text: qsTr("Local airing times")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.palette.secondary
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.weekdays
                delegate: RippleButton {
                    id: dayButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 35
                    buttonRadius: 10
                    border: true
                    borderWidth: 2
                    colBorder: activeFocus ? root.palette.mint : "transparent"
                    colBackground: modelData.key === root.selectedDay
                        ? root.palette.lavender : root.palette.panel
                    colBackgroundHover: modelData.key === root.selectedDay
                        ? root.palette.primaryHover : root.palette.cardHover
                    colRipple: root.palette.text
                    rippleEnabled: !Config.options.appearance.reducedMotion
                    rippleDuration: 140
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Show %1 schedule").arg(modelData.name)
                    Accessible.description: modelData.key === root.selectedDay ? qsTr("Selected") : ""
                    onClicked: root.selectDay(modelData.key)
                    contentItem: StyledText {
                        text: dayButton.modelData.shortName
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: dayButton.modelData.key === root.selectedDay ? Font.Medium : Font.Normal
                        color: dayButton.modelData.key === root.selectedDay
                            ? root.palette.buttonText : root.palette.secondary
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.errorMessage !== "" && root.entries.length > 0

            StyledText {
                Layout.fillWidth: true
                text: root.errorMessage
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.palette.error
            }

            RippleButton {
                implicitWidth: 64
                implicitHeight: 30
                buttonRadius: Appearance.rounding.small
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
                Accessible.name: qsTr("Retry schedule request")
                onClicked: root.retry()
                contentItem: StyledText {
                    text: qsTr("Retry")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.palette.lavender
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: scheduleList
                anchors.fill: parent
                clip: true
                spacing: 9
                animateAppearance: false
                model: root.entries
                visible: root.stateName === "ready" && root.entries.length > 0

                footer: Component {
                    RippleButton {
                        width: scheduleList.width
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
                        Accessible.name: root.loadingMore ? qsTr("Loading more scheduled anime") : qsTr("Load more scheduled anime")
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

                delegate: RippleButton {
                    id: scheduleButton
                    required property var modelData
                    width: scheduleList.width
                    height: 124
                    buttonRadius: 16
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
                    Accessible.name: qsTr("Open %1 in ani-cli, airing %2").arg(modelData.title).arg(modelData.broadcastTime)
                    onClicked: root.launchRequested(modelData.title)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 11
                        spacing: 11

                        PosterThumbnail {
                            Layout.preferredWidth: 74
                            Layout.preferredHeight: 102
                            sourceUrl: scheduleButton.modelData.imageUrl
                            palette: root.palette
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleButton.modelData.title
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: root.palette.text
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleButton.modelData.nativeTitle || scheduleButton.modelData.type
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.palette.secondary
                            }
                            Item { Layout.fillHeight: true }
                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleButton.modelData.broadcastTime
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: root.palette.mint
                            }
                            RowLayout {
                                spacing: 4
                                MaterialSymbol {
                                    text: "play_arrow"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: root.palette.lavender
                                    Accessible.ignored: true
                                }
                                StyledText {
                                    text: qsTr("Open in ani-cli")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: root.palette.lavender
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 260)
                spacing: 8
                visible: !scheduleList.visible

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.stateName === "error" ? "cloud_off"
                        : root.stateName === "loading" || root.stateName === "waiting" ? "hourglass_top"
                        : root.stateName === "empty" ? "event_busy" : "calendar_month"
                    iconSize: 30
                    color: root.stateName === "error" ? root.palette.error : root.palette.lavender
                    Accessible.ignored: true
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.stateName === "error" ? root.errorMessage
                        : root.stateName === "loading" || root.stateName === "waiting" ? qsTr("Loading %1 schedule…").arg(root.dayLabel(root.selectedDay))
                        : root.stateName === "empty" ? qsTr("No anime are listed for %1.").arg(root.dayLabel(root.selectedDay))
                        : qsTr("Choose a weekday to see its airing schedule.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.stateName === "error" ? root.palette.error : root.palette.secondary
                }

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.stateName === "error" || root.stateName === "empty"
                    implicitWidth: 100
                    implicitHeight: 36
                    buttonRadius: 11
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
                    Accessible.name: root.stateName === "error" ? qsTr("Retry schedule") : qsTr("Refresh schedule")
                    onClicked: root.stateName === "error" ? root.retry() : root.refreshSelectedDay()
                    contentItem: StyledText {
                        text: root.stateName === "error" ? qsTr("Retry") : qsTr("Refresh")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.palette.lavender
                    }
                }
            }
        }
    }
}
