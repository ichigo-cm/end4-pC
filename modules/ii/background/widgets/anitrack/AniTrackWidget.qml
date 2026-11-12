pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    // Keep the persisted slot so saved enable and placement settings survive the replacement.
    configEntryName: "commandCenter"
    hoverEnabled: true
    implicitWidth: 420
    implicitHeight: 540

    property var historyEntries: []
    property string historyState: "loading"
    property string historyError: ""
    property bool historyRefreshing: false
    property string launchStatus: ""
    property bool launchFailed: false
    property var launchCommand: []
    property double lastAniListRequestMs: 0
    property double aniListBlockedUntilMs: 0
    property double lastLaunchMs: 0
    // Keep AniTrack in the same live Material palette as the rest of the shell.
    readonly property var palette: ({
        panel: Appearance.colors.colSurfaceContainerLow,
        surface: Appearance.colors.colSurfaceContainer,
        card: Appearance.colors.colSurfaceContainerLow,
        cardHover: Appearance.colors.colPrimaryContainerHover,
        outline: Appearance.colors.colOutlineVariant,
        text: Appearance.colors.colOnSurface,
        secondary: Appearance.colors.colOnSurfaceVariant,
        muted: Appearance.colors.colOnSurfaceVariant,
        lavender: Appearance.colors.colPrimary,
        mint: Appearance.colors.colSecondary,
        blush: Appearance.colors.colTertiary,
        error: Appearance.colors.colError,
        errorContainer: Appearance.colors.colErrorContainer,
        buttonText: Appearance.colors.colOnPrimary,
        primaryHover: Appearance.colors.colPrimaryHover
    })
    readonly property bool detailOpen: tabBar.currentIndex === 0 && searchView.selectedAnime !== null
    // The standalone browser app replaces the embedded QtWebEngine experiment.
    readonly property bool webExperienceHostSupportsWebEngine: false

    function cssColor(value) {
        const alpha = Number(value.a);
        return `rgba(${Math.round(value.r * 255)}, ${Math.round(value.g * 255)}, ${Math.round(value.b * 255)}, ${alpha.toFixed(3)})`;
    }

    readonly property var webState: ({
        currentTab: tabBar.currentIndex,
        detailOpen: root.detailOpen,
        selectedAnime: searchView.selectedAnime,
        search: ({
            results: searchView.results,
            state: searchView.requestState,
            error: searchView.errorMessage,
            submittedQuery: searchView.submittedQuery,
            hasNextPage: searchView.hasNextPage,
            loadingMore: searchView.loadingMore
        }),
        schedule: ({
            entries: scheduleView.entries,
            state: scheduleView.stateName,
            error: scheduleView.errorMessage,
            selectedDay: scheduleView.selectedDay,
            weekdays: scheduleView.weekdays,
            hasNextPage: scheduleView.hasNextPage,
            loadingMore: scheduleView.loadingMore
        }),
        history: ({
            entries: root.historyEntries,
            state: root.historyState,
            error: root.historyError,
            refreshing: root.historyRefreshing,
            artwork: historyView.artworkCache
        }),
        launch: ({status: root.launchStatus, failed: root.launchFailed}),
        theme: ({
            panel: root.cssColor(root.palette.panel),
            surface: root.cssColor(root.palette.surface),
            card: root.cssColor(root.palette.card),
            hover: root.cssColor(root.palette.cardHover),
            outline: root.cssColor(root.palette.outline),
            text: root.cssColor(root.palette.text),
            secondary: root.cssColor(root.palette.secondary),
            primary: root.cssColor(root.palette.lavender),
            mint: root.cssColor(root.palette.mint),
            error: root.cssColor(root.palette.error),
            errorContainer: root.cssColor(root.palette.errorContainer),
            onPrimary: root.cssColor(root.palette.buttonText),
            colorScheme: Appearance.m3colors.darkmode ? "dark" : "light",
            fontMain: Appearance.font.family.main,
            reducedMotion: Config.options.appearance.reducedMotion
        })
    })


    function aniListDelayMs() {
        const minimumIntervalMs = 2200;
        return Math.max(0, minimumIntervalMs - (Date.now() - lastAniListRequestMs), aniListBlockedUntilMs - Date.now());
    }

    function claimAniListRequest() {
        if (aniListDelayMs() > 0)
            return false;
        lastAniListRequestMs = Date.now();
        return true;
    }

    function noteAniListRateLimit(retryAfter) {
        const value = String(retryAfter || "").trim();
        const seconds = Number(value);
        const parsedDate = Date.parse(value);
        const delay = Number.isFinite(seconds) && seconds > 0
            ? seconds * 1000
            : (!isNaN(parsedDate) ? Math.max(1000, parsedDate - Date.now()) : 60000);
        aniListBlockedUntilMs = Math.max(aniListBlockedUntilMs, Date.now() + delay);
    }

    function refreshHistory() {
        if (historyReader.running)
            return;
        historyRefreshing = true;
        historyError = "";
        if (historyEntries.length === 0)
            historyState = "loading";
        historyReader.running = true;
    }

    function refreshCurrentSection() {
        if (tabBar.currentIndex === 0)
            searchView.refreshSearch();
        else if (tabBar.currentIndex === 1)
            scheduleView.refreshSelectedDay();
        else
            refreshHistory();
    }

    function acceptHistory(raw) {
        try {
            const result = JSON.parse(raw);
            if (!result.ok) {
                historyError = result.error || qsTr("Could not read ani-cli history.");
                historyState = historyEntries.length > 0 ? "ready" : "error";
                historyRefreshing = false;
                return;
            }
            historyEntries = Array.isArray(result.entries) ? result.entries : [];
            const malformed = Number(result.malformed) || 0;
            historyError = malformed > 0
                ? qsTr("Skipped %1 malformed history row(s). Valid rows are still shown.").arg(malformed)
                : "";
            historyState = !result.historyFound ? "missing"
                : historyEntries.length > 0 ? "ready"
                : malformed > 0 ? "error" : "empty";
            historyRefreshing = false;
        } catch (error) {
            historyError = qsTr("ani-cli returned unreadable history data.");
            historyState = historyEntries.length > 0 ? "ready" : "error";
            historyRefreshing = false;
            console.warn("[AniTrackWidget] Could not parse ani-cli history:", error);
        }
    }

    function openAniCli(title) {
        if (launchProcess.running || Date.now() - lastLaunchMs < 1200)
            return;
        const cleanTitle = String(title || "").replace(/[\r\n]/g, " ").trim();
        if (!cleanTitle)
            return;
        lastLaunchMs = Date.now();
        launchStatus = qsTr("Opening ani-cli in your terminal…");
        launchFailed = false;
        launchCommand = ["launch", "--terminal", Config.options.apps.terminal,
            `--title=${cleanTitle}`];
        launchProcess.running = true;
    }

    function continueAniCliHistory() {
        if (launchProcess.running || Date.now() - lastLaunchMs < 1200)
            return;
        lastLaunchMs = Date.now();
        launchStatus = qsTr("Opening ani-cli history…");
        launchFailed = false;
        launchCommand = ["launch", "--terminal", Config.options.apps.terminal,
            "--continue"];
        launchProcess.running = true;
    }

    function acceptLaunchOutput(raw) {
        if (!raw.trim())
            return;
        try {
            const result = JSON.parse(raw);
            launchFailed = !result.ok;
            launchStatus = result.ok
                ? result.message : (result.error || qsTr("Could not start ani-cli."));
        } catch (error) {
            launchFailed = true;
            launchStatus = qsTr("Could not read the terminal launch result.");
            console.warn("[AniTrackWidget] Could not parse launch result:", error);
        }
        clearLaunchStatus.restart();
    }

    Component.onCompleted: refreshHistory()
    onVisibleChanged: {
        if (!visible)
            return;
        if (tabBar.currentIndex === 1)
            scheduleView.loadSelectedDay();
        else if (tabBar.currentIndex === 2)
            refreshHistory();
    }

    Process {
        id: historyReader
        command: ["python3", Quickshell.shellPath("modules/ii/background/widgets/anitrack/ani_cli_bridge.py"), "read-history"]
        stdout: StdioCollector {
            id: historyOutput
            onStreamFinished: root.acceptHistory(historyOutput.text)
        }
        stderr: StdioCollector { id: historyErrorOutput }
        onExited: (code, status) => {
            if (code !== 0) {
                const errorText = historyErrorOutput.text.trim()
                    || qsTr("Could not read ani-cli history. Check that Python 3 is installed.");
                if (root.historyState === "loading" || root.historyEntries.length === 0)
                    root.historyState = "error";
                root.historyError = errorText;
            }
            root.historyRefreshing = false;
        }
    }

    Process {
        id: launchProcess
        command: ["python3", Quickshell.shellPath("modules/ii/background/widgets/anitrack/ani_cli_bridge.py"), ...root.launchCommand]
        stdout: StdioCollector {
            id: launchOutput
            onStreamFinished: root.acceptLaunchOutput(launchOutput.text)
        }
        stderr: StdioCollector { id: launchErrorOutput }
        onExited: (code, status) => {
            if (code !== 0 && root.launchStatus.startsWith(qsTr("Opening"))) {
                root.launchFailed = true;
                root.launchStatus = launchErrorOutput.text.trim()
                    || qsTr("Could not start ani-cli or the configured terminal.");
                clearLaunchStatus.restart();
            }
        }
    }

    Timer {
        id: clearLaunchStatus
        interval: 7000
        repeat: false
        onTriggered: root.launchStatus = ""
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible && tabBar.currentIndex === 2
        onTriggered: root.refreshHistory()
    }

    Loader {
        id: webExperienceLoader
        anchors.fill: parent
        anchors.margins: 14
        z: 10
        // Keep Chromium uninstantiated inside Quickshell; the local app runs in the user's browser.
        active: false
        asynchronous: true
        visible: true
        enabled: item ? item.pageReady : false
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("[AniTrackWidget] WebEngine frontend unavailable; retaining the native QML UI.");
        }
    }

    Binding {
        target: webExperienceLoader.item
        property: "state"
        value: root.webState
        when: webExperienceLoader.status === Loader.Ready
    }

    Connections {
        target: webExperienceLoader.item
        ignoreUnknownSignals: true
        function onSearchRequested(query) { searchView.searchFromWeb(query); }
        function onRefreshRequested() { root.refreshCurrentSection(); }
        function onLoadMoreSearchRequested() { searchView.loadMore(); }
        function onLoadMoreScheduleRequested() { scheduleView.loadMore(); }
        function onTabRequested(index) { tabBar.currentIndex = index; }
        function onDayRequested(day) { scheduleView.selectDay(day); }
        function onAnimeSelected(anime) { searchView.openDetails(anime); }
        function onDetailClosed() { searchView.closeDetails(); }
        function onTitleLaunched(title) { root.openAniCli(title); }
        function onContinueHistoryRequested() { root.continueAniCliHistory(); }
        function onOpenAniListRequested() { Qt.openUrlExternally("https://anilist.co"); }
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        widget: root

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            visible: webExperienceLoader.status !== Loader.Ready || !webExperienceLoader.item.pageReady
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 11

                MaterialShapeWrappedMaterialSymbol {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                    text: "movie"
                    iconSize: 20
                    fill: 1
                    padding: 8
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: qsTr("AniTrack")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: root.palette.text
                    }
                    StyledText {
                        text: root.detailOpen ? qsTr("A closer look at this story")
                            : tabBar.currentIndex === 0 ? qsTr("Find a story for tonight")
                            : tabBar.currentIndex === 1
                                ? qsTr("Airing by weekday")
                                : qsTr("Your ani-cli watch history")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.palette.secondary
                    }
                }

                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: 12
                    border: true
                    borderWidth: 2
                    colBorder: activeFocus ? root.palette.mint : root.palette.outline
                    colBackground: root.palette.panel
                    colBackgroundHover: root.palette.cardHover
                    colRipple: root.palette.lavender
                    rippleEnabled: !Config.options.appearance.reducedMotion
                    rippleDuration: 140
                    activeFocusOnTab: true
                    enabled: tabBar.currentIndex === 0
                        ? searchView.requestState !== "loading" && searchView.requestState !== "waiting"
                        : tabBar.currentIndex === 1
                            ? scheduleView.stateName !== "loading" && scheduleView.stateName !== "waiting"
                            : !root.historyRefreshing
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Refresh current AniTrack section")
                    onClicked: root.refreshCurrentSection()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: tabBar.currentIndex === 0 && (searchView.requestState === "loading" || searchView.requestState === "waiting")
                            || tabBar.currentIndex === 1 && (scheduleView.stateName === "loading" || scheduleView.stateName === "waiting")
                            || tabBar.currentIndex === 2 && root.historyRefreshing
                            ? "hourglass_top" : "refresh"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.palette.secondary
                        Accessible.ignored: true
                    }
                }
            }

            SecondaryTabBar {
                id: tabBar
                Layout.fillWidth: true
                Layout.preferredHeight: 39
                spacing: 0
                indicatorPadding: 10
                onCurrentIndexChanged: {
                    if (currentIndex === 1)
                        scheduleView.loadSelectedDay();
                    else if (currentIndex === 2)
                        root.refreshHistory();
                }
                TabButton {
                    id: discoverTab
                    width: tabBar.width / 3
                    text: qsTr("Discover")
                    activeFocusOnTab: true
                    Accessible.name: text
                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 8
                            color: "transparent"
                            border.width: discoverTab.activeFocus ? 1 : 0
                            border.color: root.palette.mint
                            Accessible.ignored: true
                        }
                    }
                    contentItem: StyledText {
                        text: discoverTab.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: discoverTab.checked ? Font.Medium : Font.Normal
                        color: discoverTab.checked ? root.palette.text : root.palette.secondary
                        Behavior on color {
                            ColorAnimation {
                                duration: Config.options.appearance.reducedMotion ? 0 : 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                TabButton {
                    id: airingTab
                    width: tabBar.width / 3
                    text: qsTr("Airing")
                    activeFocusOnTab: true
                    Accessible.name: text
                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 8
                            color: "transparent"
                            border.width: airingTab.activeFocus ? 1 : 0
                            border.color: root.palette.mint
                            Accessible.ignored: true
                        }
                    }
                    contentItem: StyledText {
                        text: airingTab.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: airingTab.checked ? Font.Medium : Font.Normal
                        color: airingTab.checked ? root.palette.text : root.palette.secondary
                        Behavior on color {
                            ColorAnimation {
                                duration: Config.options.appearance.reducedMotion ? 0 : 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                TabButton {
                    id: historyTab
                    width: tabBar.width / 3
                    text: qsTr("My History")
                    activeFocusOnTab: true
                    Accessible.name: text
                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 8
                            color: "transparent"
                            border.width: historyTab.activeFocus ? 1 : 0
                            border.color: root.palette.mint
                            Accessible.ignored: true
                        }
                    }
                    contentItem: StyledText {
                        text: historyTab.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: historyTab.checked ? Font.Medium : Font.Normal
                        color: historyTab.checked ? root.palette.text : root.palette.secondary
                        Behavior on color {
                            ColorAnimation {
                                duration: Config.options.appearance.reducedMotion ? 0 : 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabBar.currentIndex

                AnimeSearchView {
                    id: searchView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    apiCoordinator: root
                    palette: root.palette
                    onLaunchRequested: title => root.openAniCli(title)
                }

                AnimeScheduleView {
                    id: scheduleView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    apiCoordinator: root
                    palette: root.palette
                    onLaunchRequested: title => root.openAniCli(title)
                }

                AniCliHistoryView {
                    id: historyView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    entries: root.historyEntries
                    webArtworkEnabled: webExperienceLoader.status === Loader.Ready && tabBar.currentIndex === 2
                    stateName: root.historyState
                    errorMessage: root.historyError
                    refreshing: root.historyRefreshing
                    apiCoordinator: root
                    palette: root.palette
                    onRefreshRequested: root.refreshHistory()
                    onContinueRequested: root.continueAniCliHistory()
                    onTitleRequested: title => root.openAniCli(title)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Appearance.rounding.small
                color: root.launchFailed
                    ? root.palette.errorContainer : root.palette.surface
                visible: root.launchStatus !== ""
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7
                    MaterialSymbol {
                        text: root.launchFailed ? "error_outline" : "info"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.launchFailed
                            ? root.palette.error : root.palette.mint
                        Accessible.ignored: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.launchStatus
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.palette.text
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 8

                RippleButton {
                    implicitWidth: 122
                    implicitHeight: 26
                    buttonRadius: 7
                    border: true
                    borderWidth: 2
                    colBorder: activeFocus ? root.palette.mint : "transparent"
                    colBackground: "transparent"
                    colBackgroundHover: root.palette.surface
                    colRipple: root.palette.lavender
                    rippleEnabled: !Config.options.appearance.reducedMotion
                    rippleDuration: 140
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Link
                    Accessible.name: qsTr("Powered by AniList; open AniList website")
                    onClicked: Qt.openUrlExternally("https://anilist.co")
                    contentItem: StyledText {
                        text: qsTr("Powered by AniList")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.palette.secondary
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: root.detailOpen ? ""
                        : tabBar.currentIndex === 0
                            ? (searchView.requestState === "ready" || searchView.requestState === "empty"
                                ? qsTr("%n titles", "AniList result count", searchView.results.length) : "")
                            : tabBar.currentIndex === 1
                                ? (scheduleView.stateName === "ready" || scheduleView.stateName === "empty"
                                    ? qsTr("%n airing", "Airing schedule count", scheduleView.entries.length) : "")
                                : (root.historyState === "ready" || root.historyState === "empty" || root.historyState === "missing"
                                    ? qsTr("%n saved", "ani-cli history count", root.historyEntries.length) : "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.palette.muted
                }
            }
        }
    }
}
