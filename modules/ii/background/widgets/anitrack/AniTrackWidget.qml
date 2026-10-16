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
    property double lastJikanRequestMs: 0
    property double jikanBlockedUntilMs: 0
    property double lastLaunchMs: 0

    function jikanDelayMs() {
        return Math.max(0, 1200 - (Date.now() - lastJikanRequestMs), jikanBlockedUntilMs - Date.now());
    }

    function claimJikanRequest() {
        if (jikanDelayMs() > 0)
            return false;
        lastJikanRequestMs = Date.now();
        return true;
    }

    function noteJikanRateLimit(retryAfter) {
        const value = String(retryAfter || "").trim();
        const seconds = Number(value);
        const parsedDate = Date.parse(value);
        const delay = Number.isFinite(seconds) && seconds > 0
            ? seconds * 1000
            : (!isNaN(parsedDate) ? Math.max(1000, parsedDate - Date.now()) : 60000);
        jikanBlockedUntilMs = Math.max(jikanBlockedUntilMs, Date.now() + delay);
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
        if (visible && tabBar.currentIndex === 1)
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
        running: root.visible && tabBar.currentIndex === 1
        onTriggered: root.refreshHistory()
    }

    WidgetCard {
        id: card
        anchors.fill: parent
        widget: root

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 11

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "movie_edit"
                        iconSize: 22
                        color: Appearance.colors.colOnPrimaryContainer
                        Accessible.ignored: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: qsTr("AniTrack")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: tabBar.currentIndex === 0
                            ? qsTr("Discover something to watch")
                            : qsTr("%1 titles saved by ani-cli").arg(root.historyEntries.length)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            SecondaryTabBar {
                id: tabBar
                Layout.fillWidth: true
                onCurrentIndexChanged: {
                    if (currentIndex === 1)
                        root.refreshHistory();
                }
                SecondaryTabButton {
                    buttonIcon: "search"
                    buttonText: qsTr("Discover")
                }
                SecondaryTabButton {
                    buttonIcon: "history"
                    buttonText: qsTr("My History")
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabBar.currentIndex

                AnimeSearchView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    apiCoordinator: root
                    onLaunchRequested: title => root.openAniCli(title)
                }

                AniCliHistoryView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    entries: root.historyEntries
                    stateName: root.historyState
                    errorMessage: root.historyError
                    refreshing: root.historyRefreshing
                    apiCoordinator: root
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
                    ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer1
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
                            ? Appearance.colors.colError : Appearance.colors.colPrimary
                        Accessible.ignored: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.launchStatus
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.launchFailed
                            ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
