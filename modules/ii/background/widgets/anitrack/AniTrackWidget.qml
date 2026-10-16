pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    // Keep the existing persisted key so current enable/placement settings carry over.
    configEntryName: "commandCenter"
    hoverEnabled: true
    implicitWidth: 340
    implicitHeight: 300

    property var watchedEntries: []
    property string historyState: "loading" // loading, ready, empty, missing, error
    property string historyError: ""

    property var releaseEntries: []
    property string releaseState: "idle" // idle, loading, ready, partial, error
    property string releaseError: ""
    property var releaseAccumulator: []
    property var scheduleRequest: null
    property int nextSchedulePage: 1
    property double lastScheduleRefreshMs: 0
    property bool releaseRefreshCooldown: false

    function refreshHistory() {
        if (historyReader.running)
            return;
        historyState = "loading";
        historyError = "";
        historyReader.running = true;
    }

    function acceptHistoryResponse(raw) {
        try {
            const result = JSON.parse(raw);
            if (!result.ok) {
                historyState = "error";
                historyError = result.error || "AniTrack history could not be read.";
                return;
            }

            watchedEntries = Array.isArray(result.entries) ? result.entries : [];
            if (!result.databaseFound)
                historyState = "missing";
            else if (watchedEntries.length === 0)
                historyState = "empty";
            else
                historyState = "ready";
        } catch (error) {
            historyState = "error";
            historyError = "AniTrack returned unreadable history data.";
            console.warn("[AniTrackWidget] Failed to parse local history:", error);
        }
    }

    function progressRatio(entry) {
        const episode = Number(entry?.last_episode);
        const total = Number(entry?.total_episodes);
        if (isNaN(episode) || isNaN(total) || total <= 0)
            return 0;
        return Math.max(0, Math.min(1, episode / total));
    }

    function progressLabel(entry) {
        const episode = entry?.last_episode === null || entry?.last_episode === undefined
            ? "?" : String(entry.last_episode);
        const total = Number(entry?.total_episodes);
        const progress = !isNaN(total) && total > 0
            ? `EP ${episode} / ${total}` : `EP ${episode}`;
        return `${progress}  ·  ${formatLastSeen(entry?.last_seen_at)}`;
    }

    function formatLastSeen(value) {
        if (!value)
            return "date unavailable";
        const date = new Date(value);
        if (isNaN(date.getTime()))
            return "date unavailable";
        return Qt.formatDateTime(date, "MMM d");
    }

    function ensureScheduleFresh() {
        const stale = lastScheduleRefreshMs > 0
            && Date.now() - lastScheduleRefreshMs > 6 * 60 * 60 * 1000;
        if (releaseState === "idle" || (releaseState === "ready" && stale))
            refreshSchedule();
    }

    function refreshSchedule() {
        if (releaseState === "loading" || releaseRefreshCooldown)
            return;
        releaseRefreshCooldown = true;
        scheduleRefreshCooldown.restart();
        if (scheduleRequest) {
            scheduleRequest.abort();
            scheduleRequest = null;
        }
        schedulePageDelay.stop();
        scheduleRequestTimeout.stop();
        releaseAccumulator = [];
        releaseEntries = [];
        releaseError = "";
        releaseState = "loading";
        nextSchedulePage = 1;
        fetchSchedulePage(1);
    }

    function fetchSchedulePage(page) {
        if (releaseState !== "loading")
            return;

        const request = new XMLHttpRequest();
        scheduleRequest = request;
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            if (root.scheduleRequest !== request)
                return;

            root.scheduleRequest = null;
            scheduleRequestTimeout.stop();

            if (request.status !== 200) {
                let message = `Schedule service returned HTTP ${request.status}.`;
                if (request.status === 429)
                    message = "The schedule service is rate-limited. Try again later.";
                else if (request.status === 0)
                    message = "Could not reach the schedule service.";
                root.failSchedule(message);
                return;
            }

            try {
                const response = JSON.parse(request.responseText);
                if (!Array.isArray(response.data)) {
                    root.failSchedule("The schedule service returned an unexpected response.");
                    return;
                }

                root.releaseAccumulator = root.releaseAccumulator.concat(response.data);
                const hasNextPage = response.pagination?.has_next_page === true;
                if (hasNextPage && page < 12) {
                    root.nextSchedulePage = page + 1;
                    schedulePageDelay.restart();
                    return;
                }

                root.releaseEntries = root.normalizeSchedule(root.releaseAccumulator);
                root.releaseState = hasNextPage ? "partial" : "ready";
                root.releaseError = hasNextPage
                    ? "Showing the first 12 pages of this week's schedule." : "";
                root.lastScheduleRefreshMs = Date.now();
            } catch (error) {
                root.failSchedule("Could not read the schedule response.");
                console.warn("[AniTrackWidget] Failed to parse schedule:", error);
            }
        };

        request.open("GET", `https://api.jikan.moe/v4/schedules?limit=25&page=${page}`);
        request.setRequestHeader("Accept", "application/json");
        request.send();
        scheduleRequestTimeout.restart();
    }

    function failSchedule(message) {
        releaseEntries = normalizeSchedule(releaseAccumulator);
        releaseError = message;
        releaseState = releaseEntries.length > 0 ? "partial" : "error";
    }

    function normalizeSchedule(items) {
        const dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
        function dayIndex(day) {
            const normalized = String(day || "").toLowerCase();
            return dayNames.findIndex(name => normalized.startsWith(name));
        }
        function timeMinutes(time) {
            const match = String(time || "").match(/(\d{1,2}):(\d{2})/);
            return match ? Number(match[1]) * 60 + Number(match[2]) : 9999;
        }

        return items
            .filter(item => item && typeof item === "object")
            .map(item => {
                const broadcast = item.broadcast || {};
                return {
                    title: String(item.title_english || item.title || item.title_japanese || "Untitled anime"),
                    day: String(broadcast.day || ""),
                    time: String(broadcast.time || ""),
                    timezone: String(broadcast.timezone || ""),
                    scheduleText: String(broadcast.string || "")
                };
            })
            .sort((left, right) => {
                const byDay = dayIndex(left.day) - dayIndex(right.day);
                if (byDay !== 0)
                    return byDay;
                return timeMinutes(left.time) - timeMinutes(right.time);
            });
    }

    function scheduleDescription(entry) {
        if (entry?.scheduleText)
            return entry.scheduleText;
        const parts = [entry?.day, entry?.time, entry?.timezone].filter(value => !!value);
        return parts.length > 0 ? parts.join("  ·  ") : "Broadcast time not listed";
    }

    function scheduleDay(entry) {
        const day = String(entry?.day || "").trim();
        return day.length > 0 ? day.slice(0, 3).toUpperCase() : "TBA";
    }

    function scheduleTime(entry) {
        return entry?.time || "--:--";
    }

    Component.onCompleted: refreshHistory()
    Component.onDestruction: {
        schedulePageDelay.stop();
        scheduleRequestTimeout.stop();
        if (scheduleRequest) {
            const request = scheduleRequest;
            scheduleRequest = null;
            request.abort();
        }
    }

    Process {
        id: historyReader
        command: ["python3", Quickshell.shellPath("modules/ii/background/widgets/anitrack/read_anitrack.py")]
        stdout: StdioCollector {
            id: historyOutput
            onStreamFinished: root.acceptHistoryResponse(historyOutput.text)
        }
        stderr: StdioCollector { id: historyErrorOutput }
        onExited: (code, status) => {
            if (code !== 0 && root.historyState === "loading") {
                root.historyState = "error";
                root.historyError = historyErrorOutput.text.trim()
                    || "Could not read AniTrack history. Check that Python 3 is installed.";
            }
        }
    }

    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: root.refreshHistory()
    }

    Timer {
        id: schedulePageDelay
        interval: 500
        repeat: false
        onTriggered: root.fetchSchedulePage(root.nextSchedulePage)
    }

    Timer {
        id: scheduleRequestTimeout
        interval: 15 * 1000
        repeat: false
        onTriggered: {
            if (!root.scheduleRequest)
                return;
            const request = root.scheduleRequest;
            root.scheduleRequest = null;
            request.abort();
            root.failSchedule("The schedule request timed out.");
        }
    }

    Timer {
        interval: 6 * 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: {
            if (tabBar.currentIndex === 1)
                root.refreshSchedule();
        }
    }

    Timer {
        id: scheduleRefreshCooldown
        interval: 10 * 1000
        repeat: false
        onTriggered: root.releaseRefreshCooldown = false
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        widget: root

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "movie"
                        iconSize: 21
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: "AniTrack"
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: tabBar.currentIndex === 0 ? "LOCAL WATCH HISTORY" : "WEEKLY AIRINGS"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        font.letterSpacing: 0.7
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.normal
                    enabled: tabBar.currentIndex === 0 ? !historyReader.running
                        : root.releaseState !== "loading" && !root.releaseRefreshCooldown
                    onClicked: tabBar.currentIndex === 0 ? root.refreshHistory() : root.refreshSchedule()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip {
                        text: tabBar.currentIndex === 0 ? "Refresh AniTrack history" : "Refresh weekly schedule"
                    }
                }
            }

            SecondaryTabBar {
                id: tabBar
                Layout.fillWidth: true
                onCurrentIndexChanged: {
                    if (currentIndex === 1)
                        root.ensureScheduleFresh();
                }

                SecondaryTabButton {
                    buttonIcon: "history"
                    buttonText: "My AniTrack"
                }
                SecondaryTabButton {
                    buttonIcon: "calendar_view_week"
                    buttonText: "Releases"
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabBar.currentIndex

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledListView {
                        id: historyList
                        anchors.fill: parent
                        clip: true
                        spacing: 2
                        animateAppearance: false
                        model: root.watchedEntries
                        visible: root.historyState === "ready" && root.watchedEntries.length > 0

                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: historyList.width
                            height: 54

                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    bottom: parent.bottom
                                    bottomMargin: 5
                                }
                                spacing: 9

                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 38
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colPrimaryContainer
                                    StyledText {
                                        anchors.centerIn: parent
                                        width: parent.width - 4
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        text: modelData.last_episode === null || modelData.last_episode === undefined
                                            ? "?" : String(modelData.last_episode)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.title || "Untitled anime"
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.progressLabel(modelData)
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: 2
                                radius: height / 2
                                color: Appearance.colors.colOutlineVariant
                                Rectangle {
                                    width: parent.width * root.progressRatio(modelData)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        spacing: 6
                        visible: !historyList.visible
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.historyState === "loading" ? "hourglass_top"
                                : root.historyState === "error" ? "error_outline" : "visibility_off"
                            iconSize: 26
                            color: root.historyState === "error" ? Appearance.colors.colError : Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: root.historyState === "loading" ? "Reading AniTrack…"
                                : root.historyState === "missing" ? "AniTrack data not found"
                                : root.historyState === "error" ? "Could not read AniTrack"
                                : "No shows tracked yet"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.historyState === "missing"
                                ? "Play an episode through AniTrack and your local history will appear here."
                                : root.historyState === "error" ? root.historyError
                                : root.historyState === "loading" ? "Reading your local watch history."
                                : "Your AniTrack watch history will show here."
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledListView {
                            id: releaseList
                            anchors.fill: parent
                            clip: true
                            spacing: 2
                            animateAppearance: false
                            model: root.releaseEntries
                            visible: (root.releaseState === "ready" || root.releaseState === "partial")
                                && root.releaseEntries.length > 0

                            delegate: Item {
                                required property var modelData
                                width: releaseList.width
                                height: 54

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 9

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 40
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colPrimaryContainer
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 0
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.scheduleDay(modelData)
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.Bold
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.scheduleTime(modelData)
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.scheduleDescription(modelData)
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            spacing: 6
                            visible: !releaseList.visible
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.releaseState === "loading" ? "hourglass_top"
                                    : root.releaseState === "error" ? "cloud_off" : "calendar_month"
                                iconSize: 26
                                color: root.releaseState === "error" ? Appearance.colors.colError : Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.releaseState === "loading" ? "Loading this week's schedule…"
                                    : root.releaseState === "error" ? "Schedule unavailable"
                                    : "No scheduled anime found"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: root.releaseState === "error" ? root.releaseError
                                    : root.releaseState === "loading" ? "Fetching the weekly airing list from Jikan."
                                    : "Try refreshing the schedule later."
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.releaseError || "JIKAN · TIMES AS LISTED BY THE SCHEDULE SOURCE"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.releaseError ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
