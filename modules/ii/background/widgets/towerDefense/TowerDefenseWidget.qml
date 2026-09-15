import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "towerDefense"
    hoverEnabled: true

    implicitWidth: 430
    implicitHeight: 330

    component PixelButton: Rectangle {
        id: pixelButton
        property string label: ""
        property string sublabel: ""
        property bool active: false
        property bool enabledButton: true
        property color accent: "#6ee7ff"
        property var clickAction: function() {}

        radius: 4
        color: pixelButton.active ? pixelButton.accent : "#17243b"
        border.width: 1
        border.color: pixelButton.active ? "#e2f7ff" : "#385273"
        opacity: pixelButton.enabledButton ? 1 : 0.42

        Column {
            anchors.centerIn: parent
            spacing: -1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pixelButton.label
                color: pixelButton.active ? "#07111f" : "#d8efff"
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: pixelButton.sublabel !== ""
                text: pixelButton.sublabel
                color: pixelButton.active ? "#122036" : "#7fa4c7"
                font.pixelSize: 8
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: pixelButton.enabledButton
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: pixelButton.clickAction()
        }
    }

    TowerDefenseGame {
        id: game
        configEntry: root.configEntry
        boardWidth: battlefield.width
        boardHeight: battlefield.height
    }

    StyledDropShadow { target: card }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 10
        color: "#0c1528"
        border.width: 2
        border.color: "#315172"
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 7
            color: "#101d33"
            border.width: 1
            border.color: "#203a57"
        }

        // Header: a deliberately dense arcade cabinet status strip.
        Rectangle {
            id: header
            x: 8
            y: 7
            width: parent.width - 16
            height: 28
            radius: 4
            color: "#152843"
            border.width: 1
            border.color: "#35577a"

            Text {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "TOWER // DEFENSE"
                color: "#8be9fd"
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.0
            }

            Text {
                x: 138
                anchors.verticalCenter: parent.verticalCenter
                text: "W" + (game.phase === "intermission" ? (game.wave + 1) : game.wave)
                color: "#e8f6ff"
                font.pixelSize: 10
                font.bold: true
            }

            Text {
                x: 174
                anchors.verticalCenter: parent.verticalCenter
                text: "$" + game.coins
                color: "#fde68a"
                font.pixelSize: 10
                font.bold: true
            }

            Text {
                x: 225
                anchors.verticalCenter: parent.verticalCenter
                text: "HP " + game.lives
                color: game.lives <= 6 ? "#fb7185" : "#86efac"
                font.pixelSize: 10
                font.bold: true
            }

            Text {
                x: 278
                anchors.verticalCenter: parent.verticalCenter
                text: "K " + game.kills
                color: "#a5b4fc"
                font.pixelSize: 10
                font.bold: true
            }

            PixelButton {
                x: parent.width - 88
                y: 3
                width: 38
                height: 20
                label: game.paused ? "PLAY" : "PAUSE"
                active: game.paused
                accent: "#fbbf24"
                clickAction: function() { game.paused = !game.paused }
            }
            PixelButton {
                x: parent.width - 47
                y: 3
                width: 42
                height: 20
                label: game.speed + "x"
                sublabel: "SPD"
                clickAction: function() { game.cycleSpeed() }
            }
        }

        Item {
            id: battlefieldFrame
            x: 14
            y: 42
            width: parent.width - 28
            height: 196

            Rectangle {
                anchors.fill: parent
                color: "#244b43"
                border.width: 2
                border.color: "#6b9c76"
                clip: true

                Item {
                    id: battlefield
                    anchors.fill: parent
                    clip: true

                    // Checkerboard grass makes placement cells easy to read without assets.
                    Repeater {
                        model: Math.ceil(battlefield.width / game.gridSize) * Math.ceil(battlefield.height / game.gridSize)
                        delegate: Rectangle {
                            required property int index
                            readonly property int columns: Math.ceil(battlefield.width / game.gridSize)
                            x: (index % columns) * game.gridSize
                            y: Math.floor(index / columns) * game.gridSize
                            width: game.gridSize
                            height: game.gridSize
                            color: ((Math.floor(index / columns) + index) % 2 === 0) ? "#2e5a4d" : "#295247"
                            opacity: 0.62
                            border.width: 1
                            border.color: "#24483f"
                        }
                    }

                    // Route is rendered from exactly the same waypoints used by TowerDefenseGame.
                    Repeater {
                        model: game.route.length - 1
                        delegate: Rectangle {
                            required property int index
                            readonly property var fromPoint: game.route[index]
                            readonly property var toPoint: game.route[index + 1]
                            readonly property real dx: toPoint.x - fromPoint.x
                            readonly property real dy: toPoint.y - fromPoint.y
                            x: fromPoint.x
                            y: fromPoint.y - 7
                            width: Math.sqrt(dx * dx + dy * dy) + 8
                            height: 14
                            radius: 2
                            transformOrigin: Item.Left
                            rotation: Math.atan2(dy, dx) * 180 / Math.PI
                            color: "#bd9164"
                            border.width: 2
                            border.color: "#79583f"
                        }
                    }

                    // End gate and start flag give the infinite route a readable direction.
                    Rectangle {
                        x: battlefield.width - 18
                        y: 12
                        width: 14
                        height: 28
                        color: "#26364e"
                        border.width: 2
                        border.color: "#9db4ca"
                        Rectangle { x: 2; y: 3; width: 8; height: 6; color: "#ef4444" }
                    }
                    Rectangle {
                        x: 1
                        y: battlefield.height - 34
                        width: 3
                        height: 25
                        color: "#d8eaff"
                    }
                    Rectangle {
                        x: 4
                        y: battlefield.height - 33
                        width: 12
                        height: 8
                        color: "#60a5fa"
                    }

                    // The selected tower range is only visual; game.targetFor remains authoritative.
                    Repeater {
                        model: game.towers
                        delegate: Item {
                            required property var modelData
                            readonly property var stats: game.towerStats(modelData)
                            x: modelData.x - stats.range
                            y: modelData.y - stats.range
                            width: stats.range * 2
                            height: stats.range * 2
                            visible: game.selectedTowerId === modelData.id
                            z: 1
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "#7dd3fc"
                                opacity: 0.10
                                border.width: 1
                                border.color: "#a5f3fc"
                            }
                        }
                    }

                    Repeater {
                        model: game.towers
                        delegate: Item {
                            required property var modelData
                            readonly property var definition: game.towerDefinition(modelData.type)
                            x: modelData.x - 11
                            y: modelData.y - 11
                            width: 22
                            height: 22
                            z: 4

                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: game.selectedTowerId === modelData.id ? "#d8f3ff" : "#172b43"
                                border.width: 2
                                border.color: definition.color
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: modelData.type === "cannon" ? 14 : 9
                                height: modelData.type === "arc" ? 14 : 8
                                rotation: modelData.type === "frost" ? 45 : 0
                                color: definition.color
                            }
                            Rectangle {
                                visible: modelData.type === "cannon"
                                x: 11
                                y: 8
                                width: 10
                                height: 5
                                color: "#fbd38d"
                            }
                            Rectangle {
                                visible: modelData.type === "arc"
                                anchors.centerIn: parent
                                width: 4
                                height: 18
                                color: "#fff0fd"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: -10
                                text: modelData.level
                                color: "#ffffff"
                                font.pixelSize: 8
                                font.bold: true
                                style: Text.Outline
                                styleColor: "#102138"
                            }
                        }
                    }

                    Repeater {
                        model: game.enemies
                        delegate: Item {
                            required property var modelData
                            x: modelData.x - modelData.size / 2
                            y: modelData.y - modelData.size / 2
                            width: modelData.size
                            height: modelData.size
                            z: 6

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                radius: modelData.type === "boss" ? 3 : parent.width / 2
                                color: modelData.hit > 0 ? "#ffffff" : modelData.color
                                border.width: modelData.type === "armored" || modelData.type === "boss" ? 2 : 1
                                border.color: "#17243b"
                            }
                            Rectangle {
                                x: -2
                                y: -6
                                width: parent.width + 4
                                height: 3
                                color: "#17243b"
                                Rectangle {
                                    width: parent.width * Math.max(0, modelData.hp / modelData.maxHp)
                                    height: parent.height
                                    color: modelData.type === "boss" ? "#fb7185" : "#86efac"
                                }
                            }
                            Rectangle { x: 3; y: 3; width: 2; height: 2; color: "#17243b" }
                            Rectangle { x: parent.width - 5; y: 3; width: 2; height: 2; color: "#17243b" }
                        }
                    }

                    Repeater {
                        model: game.projectiles
                        delegate: Rectangle {
                            required property var modelData
                            x: modelData.x - 3
                            y: modelData.y - 3
                            width: 6
                            height: 6
                            radius: 1
                            color: modelData.color
                            border.width: 1
                            border.color: "#ffffff"
                            z: 8
                        }
                    }

                    Rectangle {
                        id: placementPreview
                        property real previewX: 0
                        property real previewY: 0
                        visible: game.buildType !== "" && boardMouse.pointerInside
                        x: game.snapX(previewX) - 11
                        y: game.snapY(previewY) - 11
                        width: 22
                        height: 22
                        radius: 3
                        color: game.canPlaceTower(previewX, previewY) ? "#86efac" : "#fb7185"
                        opacity: 0.55
                        border.width: 2
                        border.color: "#ffffff"
                        z: 10
                    }

                    MouseArea {
                        id: boardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        property bool pointerInside: false
                        cursorShape: Qt.PointingHandCursor
                        onEntered: pointerInside = true
                        onExited: pointerInside = false
                        onPositionChanged: function(mouse) {
                            placementPreview.previewX = mouse.x
                            placementPreview.previewY = mouse.y
                        }
                        onClicked: function(mouse) { game.handleBoardClick(mouse.x, mouse.y) }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: game.paused && !game.gameOver
                        color: "#091426"
                        opacity: 0.52
                        z: 20
                        Text {
                            anchors.centerIn: parent
                            text: "PAUSED"
                            color: "#fbbf24"
                            font.pixelSize: 20
                            font.bold: true
                            font.letterSpacing: 3
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: game.gameOver
                        color: "#120d1d"
                        opacity: 0.88
                        z: 22
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "GAME OVER"
                                color: "#fb7185"
                                font.pixelSize: 21
                                font.bold: true
                                font.letterSpacing: 2
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "WAVE " + game.completedWaves + "  •  " + game.kills + " KILLS"
                                color: "#e5efff"
                                font.pixelSize: 10
                            }
                            PixelButton {
                                width: 92
                                height: 25
                                anchors.horizontalCenter: parent.horizontalCenter
                                label: "RESTART"
                                active: true
                                accent: "#86efac"
                                clickAction: function() { game.restart() }
                            }
                        }
                    }
                }
            }
        }

        // Build palette: four deliberately different tower roles, always visible.
        Row {
            id: buildPalette
            x: 14
            y: 245
            spacing: 4
            Repeater {
                model: game.towerTypes
                delegate: PixelButton {
                    required property var modelData
                    width: 43
                    height: 37
                    label: modelData.short
                    sublabel: "$" + modelData.cost
                    active: game.buildType === modelData.id
                    accent: modelData.color
                    enabledButton: !game.gameOver
                    clickAction: function() { game.selectBuild(modelData.id) }
                }
            }
        }

        Rectangle {
            id: detailPanel
            x: 198
            y: 245
            width: 218
            height: 37
            radius: 4
            color: "#152843"
            border.width: 1
            border.color: "#385273"

            Text {
                id: detailText
                x: 7
                width: 94
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (game.selectedTower)
                        return game.towerDefinition(game.selectedTower.type).name + " L" + game.selectedTower.level + "\n" + game.selectedTower.target
                    if (game.buildType !== "")
                        return game.towerDefinition(game.buildType).name + "\nclick grass"
                    return "BUILD A TOWER\ndefend the gate"
                }
                color: "#d8efff"
                font.pixelSize: 8
                font.bold: true
                lineHeight: 0.9
            }

            PixelButton {
                x: 103
                y: 4
                width: 36
                height: 29
                visible: game.selectedTower !== null
                label: game.selectedTower && game.selectedTower.level >= 5 ? "MAX" : "+"
                sublabel: game.selectedTower && game.selectedTower.level < 5 ? "$" + game.upgradeCost(game.selectedTower) : "L5"
                enabledButton: game.selectedTower !== null
                accent: "#86efac"
                clickAction: function() { game.upgradeSelected() }
            }
            PixelButton {
                x: 142
                y: 4
                width: 35
                height: 29
                visible: game.selectedTower !== null
                label: "TGT"
                sublabel: game.selectedTower ? game.selectedTower.target.slice(0, 3) : ""
                enabledButton: game.selectedTower !== null
                accent: "#a5b4fc"
                clickAction: function() { game.cycleTargetMode() }
            }
            PixelButton {
                x: 180
                y: 4
                width: 34
                height: 29
                visible: game.selectedTower !== null
                label: "SELL"
                sublabel: "65%"
                enabledButton: game.selectedTower !== null
                accent: "#fb7185"
                clickAction: function() { game.sellSelected() }
            }
        }

        Rectangle {
            id: statusStrip
            x: 14
            y: 289
            width: parent.width - 28
            height: 32
            radius: 4
            color: "#0b172a"
            border.width: 1
            border.color: "#284563"

            Text {
                x: 8
                width: 280
                anchors.verticalCenter: parent.verticalCenter
                text: game.messageTime > 0 ? game.message : (game.phase === "intermission" ? "NEXT WAVE IN " + Math.max(0, Math.ceil(game.intermission)) : "ENEMIES " + game.enemies.length)
                color: game.gameOver ? "#fb7185" : "#8ec5e8"
                font.pixelSize: 9
                font.bold: true
                elide: Text.ElideRight
            }

            PixelButton {
                x: parent.width - 96
                y: 4
                width: 91
                height: 24
                label: game.phase === "intermission" ? "NEXT WAVE" : "RESTART"
                sublabel: game.phase === "intermission" ? "SKIP WAIT" : "NEW GAME"
                active: game.phase === "intermission"
                accent: "#8be9fd"
                clickAction: function() {
                    if (game.phase === "intermission")
                        game.nextWaveNow()
                    else
                        game.restart()
                }
            }
        }
    }
}
