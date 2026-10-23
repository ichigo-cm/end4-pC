import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.settings.pages
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Item {
    id: root
    property real contentPadding: Appearance.design.isMacOS ? Appearance.design.space4 : 8
    property int currentPage: 0
    property bool showingProfile: false
    property bool isMinimal: Config.options.settings.style === "minimal"
    property string searchQuery: ""
    property int selectedSearchIndex: 0
    readonly property var searchResults: SettingsSearchIndex.search(searchQuery, 6)

    function goToTarget(target) {
        const idx = root.pages.findIndex(p => p.id === target.page);
        if (idx < 0) return;
        root.currentPage = idx;
        root.showingProfile = false;
        if (!target.label) return;

        const loader = pagesRepeater.itemAt(idx);
        if (!loader) return;
        const run = () => loader.item?.goTo(target.label, target.section, target.subsection);
        if (loader.item) {
            run();
        } else {
            const onceLoaded = () => {
                loader.loaded.disconnect(onceLoaded);
                run();
            };
            loader.loaded.connect(onceLoaded);
        }
    }

    function activateSearchResult(result) {
        if (!result) return
        root.goToTarget({
            page: result.pageId,
            label: result.kind === "page" ? "" : (result.rawLabel ?? ""),
            section: result.rawSection ?? "",
            subsection: result.rawSubsection ?? ""
        })
        searchField.text = ""
        root.forceActiveFocus()
    }

    Connections {
        target: GlobalStates
        target: GlobalStates
        function onSettingsOpenChanged() {
            if (!GlobalStates.settingsOpen) {
                searchField.text = ""
                root.selectedSearchIndex = 0
            }
        }
        function onSettingsTargetChanged() {
            const target = GlobalStates.settingsTarget;
            if (!target) return;
            root.goToTarget(target);
            GlobalStates.settingsTarget = null;
        }
    }

    onCurrentPageChanged: {
        if (root.pages[currentPage]?.id === "about") {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            Updates.refresh()
        }
    }
    
    property var pages: SettingsPages.pages

    Component.onCompleted: {
        Config.readWriteDelay = 0
        Qt.callLater(() => {
            for (let i = 0; i < root.pages.length; i++) {
                let loader = pagesRepeater.itemAt(i)
                if (loader) loader.active = true
            }
            if (profileLoader) profileLoader.active = true
        })
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Item {
            id: chromeHeader
            visible: Appearance.design.isMacOS
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 48 : 0

            RowLayout {
                anchors.fill: parent
                spacing: 12

                StyledText {
                    text: Translation.tr("Settings")
                    color: Appearance.colors.colOnLayer0
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: searchFieldWrap
                    Layout.preferredWidth: Math.min(320, Math.max(190, root.width * 0.34))
                    Layout.preferredHeight: Appearance.design.controlHeight
                    radius: Appearance.design.radiusControl
                    color: Appearance.colors.colLayer1
                    border.width: searchField.activeFocus ? 1 : 0
                    border.color: searchField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            text: "search"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }

                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            background: null
                            placeholderText: Translation.tr("Search settings")
                            placeholderTextColor: Appearance.colors.colSubtext
                            color: Appearance.colors.colOnLayer1
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.small
                            leftPadding: 0
                            rightPadding: 0
                            selectByMouse: true
                            Accessible.name: Translation.tr("Search settings")
                            onTextChanged: {
                                root.searchQuery = text
                                root.selectedSearchIndex = 0
                            }
                            onAccepted: {
                                if (root.searchResults.length > 0)
                                    root.activateSearchResult(root.searchResults[root.selectedSearchIndex])
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down && root.searchResults.length > 0) {
                                    root.selectedSearchIndex = Math.min(root.searchResults.length - 1, root.selectedSearchIndex + 1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up && root.searchResults.length > 0) {
                                    root.selectedSearchIndex = Math.max(0, root.selectedSearchIndex - 1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape && root.searchQuery.length > 0) {
                                    searchField.text = ""
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: height / 2
                    buttonText: Translation.tr("Close settings")
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: {
                        searchField.text = ""
                        GlobalStates.settingsOpen = false
                    }
                    contentItem: MaterialSymbol {
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            Rectangle {
                id: searchResultsPopup
                visible: root.searchQuery.trim().length > 0
                z: 30
                x: searchFieldWrap.mapToItem(root, 0, 0).x
                y: searchFieldWrap.mapToItem(root, 0, searchFieldWrap.height).y + 6
                width: searchFieldWrap.width
                height: Math.min(300, Math.max(54, searchResultsList.contentHeight + 12))
                radius: Appearance.design.radiusCard
                color: Appearance.colors.colUiPopupBackground
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                clip: true

                ListView {
                    id: searchResultsList
                    anchors.fill: parent
                    anchors.margins: Appearance.design.space2
                    clip: true
                    model: root.searchResults
                    currentIndex: root.selectedSearchIndex
                    visible: count > 0
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 44

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.design.radiusSmall
                            color: index === root.selectedSearchIndex ? Appearance.colors.colLayer2Hover : "transparent"
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                        text: modelData.kind === "page" ? Translation.tr("Page")
                                            : (modelData.subsection
                                                ? modelData.pageName + " · " + modelData.section + " · " + modelData.subsection
                                                : (modelData.section ? modelData.pageName + " · " + modelData.section : modelData.pageName))
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateSearchResult(modelData)
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.searchResults.length === 0
                    text: Translation.tr("No matching settings")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            Rectangle {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 0
                implicitWidth: Appearance.design.isMacOS ? (navRail.expanded ? 224 : fab.baseSize) : (navRail.expanded ? 195 : fab.baseSize)
                color: Appearance.design.isMacOS ? Appearance.colors.colLayer1 : (isMinimal ? "transparent" : Appearance.colors.colLayer1)
                radius: Appearance.design.isMacOS ? Appearance.design.radiusCard : Appearance.rounding.normal

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                NavigationRail {
                    id: navRail
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Appearance.design.isMacOS ? 12 : 20 }
                    spacing: Appearance.design.isMacOS ? 4 : 10
                    expanded: Appearance.design.isMacOS ? root.width > 640 : root.width > 900

                    Item {
                        id: profileRowContainer
                        visible: true
                        Layout.fillWidth: false
                        Layout.margins: isMinimal ? 0 : 5
                        Layout.topMargin: 15
                        Layout.bottomMargin: isMinimal ? -30 : 0
                        implicitHeight: profileRow.implicitHeight
                        implicitWidth: profileRow.implicitWidth

                        RowLayout {
                            id: profileRow
                            anchors.fill: parent
                            spacing: 10

                            UserAvatar {
                                width: 48
                                height: 48
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                visible: !isMinimal

                                StyledText {
                                    text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 100
                                }

                                StyledText {
                                    id: distroText
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 100

                                    text: {
                                        const d = Config.options.profile.descriptionText
                                        if (d === "::uptime::") return Translation.tr("Up • %1").arg(DateTime.uptime)
                                        return SystemInfo.distroName
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showingProfile = !root.showingProfile
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: isMinimal ? 50 : 160
                        Layout.topMargin: isMinimal ? 30 : -5
                        Layout.bottomMargin: isMinimal ? -30 : 0
                        height: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.2; color: Appearance.colors.colOutline }
                            GradientStop { position: 0.8; color: Appearance.colors.colOutline }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.15
                    }

                    FloatingActionButton {
                        id: fab
                        visible: !isMinimal
                        Layout.bottomMargin: -25
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }
                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: fab.justCopied = false
                        }
                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    NavigationRailTabArray {
                        currentIndex: root.currentPage
                        expanded: navRail.expanded
                        colToggled: Appearance.design.isMacOS ? (root.showingProfile ? "transparent" : Appearance.colors.colPrimaryContainer) : (root.showingProfile ? "transparent" : Appearance.colors.colSecondaryContainer)
                        Repeater {
                            model: root.pages
                            NavigationRailButton {
                                required property var index
                                required property var modelData
                                toggled: root.currentPage === index && !root.showingProfile
                                onPressed: {
                                    root.currentPage = index
                                    root.showingProfile = false
                                }
                                expanded: navRail.expanded
                                buttonIcon: modelData.icon
                                buttonIconRotation: modelData.iconRotation || 0
                                buttonText: modelData.name
                                showToggledHighlight: false
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut

                Item {
                    anchors.fill: parent

                    Repeater {
                        id: pagesRepeater
                        model: root.pages
                        Loader {
                            id: pageLoader
                            required property var modelData
                            required property var index
                            source: modelData.component

                            active: Config.ready && (root.currentPage === index || item !== null)

                            anchors.fill: parent

                            property bool isActive: root.currentPage === index && !root.showingProfile
                            opacity: isActive ? 1 : 0
                            enabled: isActive
                            visible: isActive
                            anchors.topMargin: isActive ? 0 : 12

                            onLoaded: {
                                if (root.currentPage === index) {
                                    GlobalStates.currentPageInstance = item;
                                }
                            }

                            onIsActiveChanged: {
                                if (isActive && item) {
                                    GlobalStates.currentPageInstance = item;
                                } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                    GlobalStates.currentPageInstance = null;
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.topMargin {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Loader {
                        id: profileLoader
                        active: false
                        anchors.fill: parent
                        source: Qt.resolvedUrl("pages/Profile.qml")

                        property bool isActive: root.showingProfile
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : 12

                        onIsActiveChanged: {
                            if (isActive && item) {
                                GlobalStates.currentPageInstance = item;
                            } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                GlobalStates.currentPageInstance = null;
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on anchors.topMargin {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }
}
