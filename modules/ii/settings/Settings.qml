//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Scope {
    id: root

    readonly property real sizeScale: Config.options.settings.style === "minimal" ? 0.75 : 1.0
    property bool isMinimal: Config.options.settings.style === "minimal"
    property real resizedWidth: 0
    property real resizedHeight: 0

    Component.onCompleted: {
        GlobalStates.settingsOpen = false;
    }

    Dashboard {}

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.settingsOpen && Config.options.settings.style !== "dashboard"

        function hide() {
            GlobalStates.settingsOpen = false;
        }

        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
                settingsWindow.userMoved = false;
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (panelWindow.visible) panelWindow.hide();
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            opacity: GlobalStates.settingsOpen ? 1 : 0
            z: 0
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: false
                onClicked: panelWindow.hide()
            }
        }

        Rectangle {
            id: settingsWindow
            width: Math.min(parent.width - (isMinimal ? 70 : 80), root.resizedWidth > 0 ? root.resizedWidth : 980 * sizeScale)
            height: Math.min(parent.height - 80, root.resizedHeight > 0 ? root.resizedHeight : 665 * sizeScale)
            color: Appearance.design.isMacOS
                ? CF.ColorUtils.transparentize(Appearance.design.canvas, 1 - Appearance.design.windowOpacity)
                : Appearance.colors.colUiBackground
            border.width: Config.options.settings.borderSize
            border.color: CF.ColorUtils.transparentize(Appearance.getColorFromName(Config.options.settings.borderColor), 0.8)
            radius: Appearance.design.isMacOS ? Appearance.design.radiusCard : (!isMinimal ? Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5 : Appearance.rounding.screenRounding + 5)
            z: 1

            property bool userMoved: false
            anchors.centerIn: userMoved ? undefined : parent

            opacity: GlobalStates.settingsOpen ? 1 : 0
            scale: GlobalStates.settingsOpen ? 1 : (Appearance.design.isMacOS ? 0.98 : 0.95)

            Behavior on opacity {
                NumberAnimation { duration: Appearance.design.isMacOS ? Appearance.design.motionStandard : 200; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: Appearance.design.isMacOS ? Appearance.design.motionStandard : 200; easing.type: Easing.OutCubic }
            }

            Keys.onTabPressed: (event) => {
            const count = settingsContent.pages.length;
            settingsContent.currentPage = (settingsContent.currentPage + 1) % count;
            settingsContent.showingProfile = false;
            event.accepted = true;
        }

        Keys.onBacktabPressed: (event) => {
            const count = settingsContent.pages.length;
            settingsContent.currentPage = (settingsContent.currentPage - 1 + count) % count;
            settingsContent.showingProfile = false;
            event.accepted = true;
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panelWindow.hide();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                const instance = GlobalStates.currentPageInstance;
                if (instance && instance.contentY !== undefined) {
                    const step = 60;
                    const delta = event.key === Qt.Key_Down ? step : -step;
                    const maxY = Math.max(0, (instance.contentHeight ?? 0) - instance.height);
                    instance.contentY = Math.max(0, Math.min(maxY, instance.contentY + delta));
                }
                event.accepted = true;
                return;
            }
        }

            Rectangle {
                id: dragHandle
                anchors.top: parent.top
                anchors.left: parent.left
                width: Appearance.design.isMacOS ? 160 : parent.width
                height: Appearance.design.isMacOS ? 48 : 32
                color: "transparent"
                z: 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    drag.target: settingsWindow
                    drag.axis: Drag.XAndYAxis
                    onPressed: settingsWindow.userMoved = true
                    onDoubleClicked: settingsWindow.userMoved = false
                }
            }

            SettingsContent {
                id: settingsContent
                anchors.fill: parent
            }

            Item {
                id: resizeGrip
                visible: Appearance.design.isMacOS
                width: 22
                height: 22
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                z: 5

                MaterialSymbol {
                    anchors.fill: parent
                    text: "drag_handle"
                    iconSize: 16
                    rotation: 45
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                }

                MouseArea {
                    id: resizeMouseArea
                    anchors.fill: parent
                    cursorShape: Qt.SizeFDiagCursor
                    property point startPointer: Qt.point(0, 0)
                    property real startWidth: 0
                    property real startHeight: 0

                    onPressed: mouse => {
                        startPointer = resizeMouseArea.mapToItem(panelWindow, mouse.x, mouse.y)
                        startWidth = settingsWindow.width
                        startHeight = settingsWindow.height
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        const pointer = resizeMouseArea.mapToItem(panelWindow, mouse.x, mouse.y)
                        const maxWidth = Math.max(1, panelWindow.width - 80)
                        const maxHeight = Math.max(1, panelWindow.height - 80)
                        const minWidth = Math.min(820, maxWidth)
                        const minHeight = Math.min(560, maxHeight)
                        root.resizedWidth = Math.max(minWidth, Math.min(maxWidth, startWidth + pointer.x - startPointer.x))
                        root.resizedHeight = Math.max(minHeight, Math.min(maxHeight, startHeight + pointer.y - startPointer.y))
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen; }
        function open(): void   { GlobalStates.settingsOpen = true; }
        function close(): void  { GlobalStates.settingsOpen = false; }
    }

    CompositorGlobalShortcut {
        name: "settingsToggle"
        description: "Toggles settings panel"
        onPressed: GlobalStates.settingsOpen = !GlobalStates.settingsOpen;
    }
}
