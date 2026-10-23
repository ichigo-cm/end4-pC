import QtQuick
import qs.modules.common

Rectangle {
    id: root

    property color tint: Appearance.colors.colLayer1
    property real tintOpacity: Appearance.design.isMacOS ? 0.18 : 0.35
    property real cardRadius: Appearance.rounding.large
    property Item blurSource: null

    property Item pager: null
    property int animIndex: 0
    readonly property real speed: Math.max(0.5, Config.options.settings.animationSpeed ?? 1)
    property int staggerMs: Appearance.design.isMacOS ? (Appearance.design.reducedMotion ? 4 : 18) : 45
    property real travelX: 0
    property real travelY: 0

    readonly property real entryOffsetX: Appearance.design.isMacOS ? Math.max(-72, Math.min(72, travelX)) : travelX
    readonly property real entryOffsetY: Appearance.design.isMacOS ? Math.max(-48, Math.min(48, travelY)) : travelY
    property real animScale: Appearance.design.isMacOS ? (Appearance.design.reducedMotion ? 1 : 0.94) : 0.25
    property real animOpacity: Appearance.design.isMacOS && Appearance.design.reducedMotion ? 1 : 0
    property real offsetX: Appearance.design.isMacOS && Appearance.design.reducedMotion ? 0 : entryOffsetX
    property real offsetY: Appearance.design.isMacOS && Appearance.design.reducedMotion ? 0 : entryOffsetY

    color: blurSource ? "transparent" : tint
    radius: cardRadius
    border.width: Appearance.design.isMacOS ? Appearance.design.hairlineWidth : 0
    border.color: Appearance.colors.colOutlineVariant

    transformOrigin: Item.Center
    scale: animScale
    opacity: animOpacity
    transform: Translate {
        x: root.offsetX
        y: root.offsetY
    }

    Loader {
        anchors.fill: parent
        anchors.margins: -1
        active: root.blurSource !== null

        sourceComponent: FastBlurred {
            blurSource: root.blurSource
            cardRadius: root.cardRadius + 1
            tint: root.tint
            tintOpacity: root.tintOpacity
            trackX: root.x + root.offsetX + root.animScale
            trackY: root.y + root.offsetY
        }
    }

    SequentialAnimation {
        id: enterAnim
        PauseAnimation { duration: root.animIndex * root.staggerMs }
        ParallelAnimation {
            SpringAnimation { target: root; property: "animScale"; to: 1; spring: (Appearance.design.isMacOS ? 3.2 : 2.6) * root.speed; damping: Appearance.design.isMacOS ? 0.86 : 0.32 }
            SpringAnimation { target: root; property: "offsetX"; to: 0; spring: (Appearance.design.isMacOS ? 3.2 : 2.6) * root.speed; damping: Appearance.design.isMacOS ? 0.86 : 0.32 }
            SpringAnimation { target: root; property: "offsetY"; to: 0; spring: (Appearance.design.isMacOS ? 3.2 : 2.6) * root.speed; damping: Appearance.design.isMacOS ? 0.86 : 0.32 }
            NumberAnimation { target: root; property: "animOpacity"; to: 1; duration: 220 / root.speed; easing.type: Easing.OutQuad }
        }
    }

    SequentialAnimation {
        id: exitAnim
        PauseAnimation { duration: root.animIndex * (root.staggerMs - 4) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "animScale"; to: Appearance.design.isMacOS ? 0.94 : 0.25; duration: (Appearance.design.isMacOS ? Appearance.design.motionRelaxed : 260) / root.speed; easing.type: Appearance.design.isMacOS ? Easing.InCubic : Easing.InBack }
            NumberAnimation { target: root; property: "offsetX"; to: root.entryOffsetX; duration: (Appearance.design.isMacOS ? Appearance.design.motionRelaxed : 280) / root.speed; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "offsetY"; to: root.entryOffsetY; duration: (Appearance.design.isMacOS ? Appearance.design.motionRelaxed : 280) / root.speed; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "animOpacity"; to: 0; duration: 220 / root.speed; easing.type: Easing.InQuad }
        }
    }

    Component.onCompleted: {
        if (!(Appearance.design.isMacOS && Appearance.design.reducedMotion)) enterAnim.start()
    }

    Connections {
        target: root.pager
        ignoreUnknownSignals: true
        function onPageExitRequested() {
            if (Appearance.design.isMacOS && Appearance.design.reducedMotion) root.animOpacity = 0
            else exitAnim.restart()
        }
    }
}
