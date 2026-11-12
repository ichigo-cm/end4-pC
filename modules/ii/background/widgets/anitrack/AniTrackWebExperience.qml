pragma ComponentBehavior: Bound

import QtQuick
import QtWebChannel
import QtWebEngine

Item {
    id: root

    required property var state
    property bool pageReady: false

    signal searchRequested(string query)
    signal refreshRequested()
    signal loadMoreSearchRequested()
    signal loadMoreScheduleRequested()
    signal tabRequested(int index)
    signal dayRequested(string day)
    signal animeSelected(var anime)
    signal detailClosed()
    signal titleLaunched(string title)
    signal continueHistoryRequested()
    signal openAniListRequested()

    QtObject {
        id: bridge
        WebChannel.id: "anitrack"

        property var state: root.state

        function ready() { root.pageReady = true; }
        function search(query) { root.searchRequested(String(query || "")); }
        function refresh() { root.refreshRequested(); }
        function loadMoreSearch() { root.loadMoreSearchRequested(); }
        function loadMoreSchedule() { root.loadMoreScheduleRequested(); }
        function selectTab(index) { root.tabRequested(Math.max(0, Math.min(2, Number(index) || 0))); }
        function selectDay(day) { root.dayRequested(String(day || "")); }
        function openDetails(anime) { root.animeSelected(anime); }
        function closeDetails() { root.detailClosed(); }
        function launchTitle(title) { root.titleLaunched(String(title || "")); }
        function continueHistory() { root.continueHistoryRequested(); }
        function openAniList() { root.openAniListRequested(); }
    }

    WebChannel {
        id: webChannel
        Component.onCompleted: webChannel.registerObject("anitrack", bridge)
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        url: Qt.resolvedUrl("webapp/index.html")
        webChannel: webChannel
        backgroundColor: "transparent"
        activeFocusOnPress: true

        settings.localContentCanAccessRemoteUrls: true
        settings.javascriptCanOpenWindows: false
        settings.navigateOnDropEnabled: false

        onNavigationRequested: function(request) {
            const requestedUrl = request.url.toString();
            const applicationUrl = Qt.resolvedUrl("webapp/index.html").toString();
            if (requestedUrl === applicationUrl)
                return;
            request.action = WebEngineNavigationRequest.IgnoreRequest;
        }
    }

}
