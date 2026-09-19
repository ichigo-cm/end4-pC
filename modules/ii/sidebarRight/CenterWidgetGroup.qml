import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarRight.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.card
    color: Appearance.colors.shellSurfaceRaised
    border.width: 1
    border.color: Appearance.colors.shellBorder

    NotificationList {
        anchors.fill: parent
        anchors.margins: 5
    }
}
