import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 5
    property int todoListItemPadding: 8
    property int listBottomPadding: 80
    property var previousTodoSnapshot: []
    property int cueOriginalIndex: -1
    property bool cueDone: false
    property int cueSerial: 0

    function updateTodoSnapshot() {
        const current = Todo.list.map((task, index) => ({ task: task, done: task.done, index: index }))
        let changedTask = null
        for (const previous of root.previousTodoSnapshot) {
            changedTask = current.find(entry => entry.task === previous.task && entry.done !== previous.done) ?? null
            if (changedTask) break
        }
        root.previousTodoSnapshot = current
        root.cueOriginalIndex = changedTask ? changedTask.index : -1
        if (changedTask) {
            root.cueDone = changedTask.done
            root.cueSerial += 1
        }
    }

    Component.onCompleted: root.previousTodoSnapshot = Todo.list.map((task, index) => ({ task: task, done: task.done, index: index }))

    Connections {
        target: Todo
        function onListChanged() { root.updateTodoSnapshot() }
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            property bool pendingDoneToggle: false
            property bool pendingDelete: false
            property bool enableHeightAnimation: false
            property real cueOpacity: 1

            implicitHeight: todoItemRectangle.implicitHeight
            width: ListView.view.width
            clip: true
            opacity: cueOpacity

            function playTaskChangeCueIfMatching() {
                if (root.cueSerial > 0
                        && modelData.originalIndex === root.cueOriginalIndex
                        && modelData.done === root.cueDone) {
                    cueAnimation.stop()
                    cueOpacity = 0.72
                    cueAnimation.start()
                }
            }

            Component.onCompleted: playTaskChangeCueIfMatching()
            onModelDataChanged: playTaskChangeCueIfMatching()

            Connections {
                target: root
                function onCueSerialChanged() { todoItem.playTaskChangeCueIfMatching() }
            }

            NumberAnimation {
                id: cueAnimation
                target: todoItem
                property: "cueOpacity"
                to: 1
                duration: Config.options.appearance.reducedMotion ? 120 : 170
                easing.type: Easing.OutCubic
            }

            Behavior on implicitHeight {
                enabled: enableHeightAnimation
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                id: todoItemRectangle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: todoContentRowLayout.implicitHeight
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small

                ColumnLayout {
                    id: todoContentRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right

                    StyledText {
                        id: todoContentText
                        Layout.fillWidth: true // Needed for wrapping
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.topMargin: todoListItemPadding
                        text: todoItem.modelData.content
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.bottomMargin: todoListItemPadding
                        Item {
                            Layout.fillWidth: true
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            onClicked: {
                                if (!todoItem.modelData.done)
                                    Todo.markDone(todoItem.modelData.originalIndex);
                                else
                                    Todo.markUnfinished(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: todoItem.modelData.done ? "remove_done" : "check"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            onClicked: {
                                Todo.deleteItem(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete_forever"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
