import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property string sourceUrl: ""
    property var palette: ({ panel: "#1A1928", outline: "#655C77", muted: "#B9AFCA" })

    radius: Appearance.rounding.small
    color: root.palette.panel
    border.width: 1
    border.color: root.palette.outline

    Image {
        id: poster
        anchors.fill: parent
        anchors.margins: 1
        source: root.sourceUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: Math.max(96, root.width * 2)
        sourceSize.height: Math.max(136, root.height * 2)
        layer.enabled: root.sourceUrl !== ""
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: poster.width
                height: poster.height
                radius: Math.max(0, root.radius - 1)
            }
        }
        Accessible.ignored: true
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "movie"
        iconSize: Math.min(root.width, root.height) * 0.42
        color: root.palette.muted
        visible: poster.status !== Image.Ready
        Accessible.ignored: true
    }

}
