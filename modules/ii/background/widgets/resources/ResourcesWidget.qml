import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    Component.onCompleted: ResourceUsage.consumers++
    Component.onDestruction: ResourceUsage.consumers--
    id: root
    configEntryName: "resources"
    hoverEnabled: true

    property real widgetWidth: 420
    property real cardSpacing: 12
    property real cardHeight: 120
    property real cardWidth: (widgetWidth - cardSpacing * 2) / 3
    property bool isVertical: root.configEntry.vertical ?? false
    property bool hasBattery: Battery.available

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    component TrendIndicator: Canvas {
        id: trendIndicator
        property list<real> history: []
        property color color: Appearance.colors.colPrimary
        onHistoryChanged: requestPaint()
        onColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0 || !history || history.length === 0)
                return

            const samples = []
            for (let i = 0; i < history.length; ++i) {
                const value = Number(history[i])
                if (isNaN(value) || !isFinite(value))
                    continue
                samples.push(value)
            }
            if (samples.length === 0)
                return

            ctx.strokeStyle = color
            ctx.fillStyle = color
            ctx.lineWidth = 1.5
            ctx.lineCap = "round"
            if (samples.length === 1) {
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, 1.5, 0, Math.PI * 2)
                ctx.fill()
                return
            }

            let minimum = samples[0]
            let maximum = samples[0]
            for (let i = 1; i < samples.length; ++i) {
                minimum = Math.min(minimum, samples[i])
                maximum = Math.max(maximum, samples[i])
            }
            const range = maximum - minimum
            const padding = 2
            ctx.beginPath()
            for (let i = 0; i < samples.length; ++i) {
                const x = 0.75 + (i * (width - 1.5)) / (samples.length - 1)
                const y = range === 0
                    ? height / 2
                    : height - padding - ((samples[i] - minimum) / range) * (height - 2 * padding)
                if (i === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.stroke()
        }
    }

    component StatCard: WidgetCard {
        id: statCard
        property string icon: ""
        property string value: ""
        property string label: ""
        property list<real> history: []
        property int shape: MaterialShape.Shape.Cookie12Sided
        property color bgColor: Appearance.colors.colPrimaryContainer
        property color shapeColor: Appearance.colors.colPrimary

        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight
        widget: root
        color: statCard.bgColor

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: -4

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignRight
                shape: statCard.shape
                color: statCard.shapeColor
                colSymbol: Appearance.colors.colOnPrimary
                text: statCard.icon
                iconSize: 18
                fill: 1
                padding: 6
                implicitWidth: 34
                implicitHeight: 34
            }

            Item { Layout.fillHeight: true }

            StyledText {
                text: statCard.value
                font.pixelSize: Appearance.font.pixelSize.hugeass
                font.weight: Font.Bold
                color: Appearance.colors.colOnPrimaryContainer
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: statCard.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.6
                }
                TrendIndicator {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    history: statCard.history
                    color: statCard.shapeColor
                    opacity: 0.75
                    visible: statCard.history.length > 0
                }
            }
        }
    }

    Grid {
        id: row
        columns: root.isVertical ? 1 : 3
        rows: root.isVertical ? 3 : 1
        spacing: root.cardSpacing

        move: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Config.options.appearance.reducedMotion ? 0 : 180
                easing.type: Easing.OutCubic
            }
        }

        StatCard {
            icon: "planner_review"
            value: Math.round(ResourceUsage.cpuUsage * 100) + "%"
            label: "CPU"
            history: ResourceUsage.cpuUsageHistory
            shape: MaterialShape.Shape.Gem
        }
        StatCard {
            icon: "memory"
            value: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%"
            label: "RAM"
            history: ResourceUsage.memoryUsageHistory
            shape: MaterialShape.Shape.Cookie4Sided
            bgColor: Appearance.colors.colSecondaryContainer
            shapeColor: Appearance.colors.colSecondary
        }
        StatCard {
            icon: root.hasBattery ? "battery_full" : "storage"
            value: root.hasBattery
                ? Math.round(Battery.percentage * 100) + "%"
                : Math.round(ResourceUsage.diskUsedPercentage * 100) + "%"
            label: root.hasBattery ? "Battery" : "Disk"
            history: root.hasBattery ? [] : ResourceUsage.diskUsageHistory
            shape: MaterialShape.Shape.Cookie12Sided
            bgColor: Appearance.colors.colTertiaryContainer
            shapeColor: Appearance.colors.colTertiary
        }
    }
    WidgetFlipHandle {
        anchorItem: root
        hoverActive: root.containsMouse
        locked: Config.options.background.widgetsLocked
        onClicked: {
            root.isVertical = !root.isVertical
            root.configEntry.vertical = root.isVertical
        }
    }
}
