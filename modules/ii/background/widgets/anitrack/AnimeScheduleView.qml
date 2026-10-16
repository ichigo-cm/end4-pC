pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

    function imageUrl(anime) {
        const images = anime?.images || {};
        const webp = images.webp || {};
        const jpg = images.jpg || {};
        const candidate = String(webp.image_url || jpg.image_url || "");
        return /^https:\/\//i.test(candidate) ? candidate : "";
    }

    function normalizeAnime(item) {
        const broadcast = item?.broadcast || {};
        let broadcastTime = String(broadcast.time || "");
        if (broadcastTime && broadcast.timezone)
            broadcastTime += ` · ${String(broadcast.timezone).split("/").pop().replace(/_/g, " ")}`;
        else if (!broadcastTime && broadcast.string)
            broadcastTime = String(broadcast.string);
        else if (!broadcastTime)
            broadcastTime = qsTr("Time not listed");

        return {
            id: Number(item?.mal_id) || 0,
            title: String(item?.title_english || item?.title || item?.title_japanese || qsTr("Untitled anime")),
            nativeTitle: String(item?.title_japanese || ""),
            imageUrl: imageUrl(item),
            type: String(item?.type || ""),
            broadcastTime: broadcastTime,
            score: Number(item?.score) || 0
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
        scheduleRequest.interval = Math.max(0, apiCoordinator ? apiCoordinator.jikanDelayMs() : 0);
        scheduleRequest.restart();
    }

    function issueScheduleRequest() {
        if (!apiCoordinator || !apiCoordinator.claimJikanRequest()) {
            scheduleRequest.interval = Math.max(100, apiCoordinator ? apiCoordinator.jikanDelayMs() : 1200);
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

        request.open("GET", `https://api.jikan.moe/v4/schedules?filter=${encodeURIComponent(day)}&sfw=true&limit=25&page=${page}`);
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
                    ? qsTr("Jikan is rate-limiting requests. Wait a little, then retry.")
                    : request.status === 0
                        ? qsTr("Could not reach Jikan. Check your connection and try again.")
                        : qsTr("Weekly schedule failed (HTTP %1). Retry to try again.").arg(request.status);
                root.loadingMore = false;
                root.stateName = root.entries.length > 0 ? "ready" : "error";
                return;
            }

            try {
                const response = JSON.parse(request.responseText);
                const items = Array.isArray(response.data) ? response.data : [];
                const normalized = items.map(item => root.normalizeAnime(item));
                root.entries = append ? root.entries.concat(normalized) : normalized;
                root.currentPage = page;
                root.hasNextPage = response.pagination?.has_next_page === true;
                root.loadingMore = false;
                root.errorMessage = "";
                root.stateName = root.entries.length > 0 ? "ready" : "empty";
            } catch (error) {
                root.errorMessage = qsTr("Could not read this day's schedule. Retry to try again.");
                root.loadingMore = false;
                root.stateName = root.entries.length > 0 ? "ready" : "error";
                console.warn("[AniTrackWidget] Could not parse Jikan schedule response:", error);
            }
        };
        request.send();
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
        interval: 15000
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
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: root.dayLabel(root.selectedDay)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: qsTr("Jikan airing times")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Refresh %1 schedule").arg(root.dayLabel(root.selectedDay))
                onClicked: root.refreshSelectedDay()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.stateName === "loading" || root.stateName === "waiting" || root.loadingMore
                        ? "hourglass_top" : "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                    Accessible.ignored: true
                }
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
                    buttonRadius: Appearance.rounding.small
                    colBackground: modelData.key === root.selectedDay
                        ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
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
                            ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
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
                color: Appearance.colors.colError
            }

            RippleButton {
                implicitWidth: 64
                implicitHeight: 30
                buttonRadius: Appearance.rounding.small
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Retry schedule request")
                onClicked: root.retry()
                contentItem: StyledText {
                    text: qsTr("Retry")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
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
                spacing: 5
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
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: root.loadingMore ? qsTr("Loading more scheduled anime") : qsTr("Load more scheduled anime")
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
                    id: scheduleButton
                    required property var modelData
                    width: scheduleList.width
                    height: 78
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer1
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Open %1 in ani-cli, airing %2").arg(modelData.title).arg(modelData.broadcastTime)
                    onClicked: root.launchRequested(modelData.title)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 9
                        spacing: 9

                        PosterThumbnail {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 62
                            sourceUrl: scheduleButton.modelData.imageUrl
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleButton.modelData.title
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleButton.modelData.nativeTitle || scheduleButton.modelData.type
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleButton.modelData.broadcastTime
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }

                        MaterialSymbol {
                            text: "play_circle"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                            Accessible.ignored: true
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
                    color: root.stateName === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
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
                    color: root.stateName === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
                }

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.stateName === "error" || root.stateName === "empty"
                    implicitWidth: 100
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.normal
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: root.stateName === "error" ? qsTr("Retry schedule") : qsTr("Refresh schedule")
                    onClicked: root.stateName === "error" ? root.retry() : root.refreshSelectedDay()
                    contentItem: StyledText {
                        text: root.stateName === "error" ? qsTr("Retry") : qsTr("Refresh")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
