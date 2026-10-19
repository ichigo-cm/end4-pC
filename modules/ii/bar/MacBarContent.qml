import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    readonly property bool centerOnly: false
    readonly property real menuBarHeight: 34
    readonly property color foreground: Appearance.colors.colOnLayer0
    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property string activeAppName: {
        const appId = root.activeWindow?.appId ?? "";
        if (appId === "") return Translation.tr("Desktop");
        const entry = DesktopEntries.byId(appId);
        if (entry?.name) return entry.name;
        const lastPart = appId.split(".").slice(-1)[0];
        return lastPart.replace(/[-_]/g, " ");
    }

    implicitHeight: root.menuBarHeight
    width: parent ? parent.width : 0

    Component.onCompleted: Vpn.refresh()

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.applyAlpha(Appearance.colors.colUiBackground, 0.82)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.10)
    }

    DynamicIsland {
        id: island
        width: implicitWidth
        height: implicitHeight
        vertical: false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        z: 2
    }

    Item {
        id: leftRegion
        anchors {
            left: parent.left
            leftMargin: 10
            right: island.left
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        height: parent.height
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 4

            LauncherButton {
                Layout.alignment: Qt.AlignVCenter
                isMaterial: false
                iconSize: 17
                contentColor: root.foreground
                contentColorOverridden: true
                implicitWidth: 28
                implicitHeight: 28
                Accessible.name: Translation.tr("Applications and workspaces")
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: Math.max(56, leftRegion.width - 240)
                text: root.activeAppName
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.DemiBold
                color: root.foreground
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }

            Item {
                id: settingsAction
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: settingsLabel.implicitWidth + 14
                implicitHeight: 26
                visible: leftRegion.width > 300
                activeFocusOnTab: visible
                Accessible.role: Accessible.Button
                Keys.onReturnPressed: GlobalStates.openSettingsAt("interface", Translation.tr("Interface"), Translation.tr("Desktop appearance"))
                Keys.onSpacePressed: GlobalStates.openSettingsAt("interface", Translation.tr("Interface"), Translation.tr("Desktop appearance"))

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: settingsHover.containsMouse ? Appearance.colors.colLayer0Hover : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }
                StyledText {
                    id: settingsLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Settings")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: root.foreground
                }
                MouseArea {
                    id: settingsHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GlobalStates.openSettingsAt("interface", Translation.tr("Interface"), Translation.tr("Desktop appearance"))
                }
                Accessible.name: Translation.tr("Open appearance settings")
            }
        }
    }

    Item {
        id: rightRegion
        anchors {
            left: island.right
            leftMargin: 14
            right: parent.right
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        height: parent.height
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 7

            Item { Layout.fillWidth: true }

            SysTray {
                Layout.alignment: Qt.AlignVCenter
                vertical: false
                isMaterial: false
                contentColor: root.foreground
                contentColorOverridden: true
                showSeparator: false
                showOverflowMenu: true
                visible: root.width >= 880 && SystemTray.items.values.length > 0
            }

            SystemIcons {
                Layout.alignment: Qt.AlignVCenter
                vertical: false
                iconSize: 17
                contentColor: root.foreground
                contentColorOverridden: true
                showDate: false
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("System controls")
                Keys.onReturnPressed: GlobalStates.sidebarRightOpen = true
                Keys.onSpacePressed: GlobalStates.sidebarRightOpen = true
            }

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 24
                implicitHeight: 30
                visible: Vpn.available
                activeFocusOnTab: visible
                Accessible.role: Accessible.Button
                Accessible.name: Vpn.connected ? Translation.tr("VPN connected") : Translation.tr("VPN disconnected")
                Keys.onReturnPressed: {
                    Vpn.refresh()
                    GlobalStates.sidebarRightOpen = true
                }
                Keys.onSpacePressed: {
                    Vpn.refresh()
                    GlobalStates.sidebarRightOpen = true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: Vpn.connected ? "vpn_lock" : "vpn_key_off"
                    iconSize: 17
                    color: Vpn.connected ? root.foreground : Appearance.colors.colSubtext
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Vpn.refresh()
                        GlobalStates.sidebarRightOpen = true
                    }
                }

                StyledToolTip {
                    text: Vpn.connected ? Translation.tr("VPN connected") : Translation.tr("VPN disconnected")
                }
            }

            BatteryIndicator {
                Layout.alignment: Qt.AlignVCenter
                vertical: false
                isMaterial: false
                contentColor: root.foreground
                contentColorOverridden: true
                visible: root.width >= 720
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 7
                visible: root.width >= 700

                StyledText {
                    text: DateTime.shortDate
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: root.foreground
                }

                ClockWidget {
                    Layout.alignment: Qt.AlignVCenter
                    vertical: false
                    isMaterial: false
                    showDate: false
                    contentColor: root.foreground
                    contentColorOverridden: true
                    timePixelSize: Appearance.font.pixelSize.smallie
                    implicitHeight: 30
                }
            }
        }
    }
}
