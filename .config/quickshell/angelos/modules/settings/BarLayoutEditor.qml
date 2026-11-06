pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services
import qs.widgets

// Drag widgets between Слева / Центр / Справа / Скрыто (like Noctalia's bar editor).
Item {
    id: root

    readonly property var columns: [
        {
            "id": "left",
            "label": I18n.t("Слева", "Left")
        },
        {
            "id": "center",
            "label": I18n.t("Центр", "Center")
        },
        {
            "id": "right",
            "label": I18n.t("Справа", "Right")
        },
        {
            "id": "hidden",
            "label": I18n.t("Скрыто", "Hidden")
        }
    ]
    function listFor(col) {
        // the lanes keep their disabled widgets (dimmed, the eye switches them back on); only
        // "Hidden" takes a widget out of the layout for good
        return col === "hidden" ? BarLayout.hidden : BarLayout.arranged[col];
    }

    property string dragId: ""
    property point dragPos
    property string dropCol: ""
    property int dropIndex: -1

    implicitHeight: row.implicitHeight + Theme.u * 4
    width: parent ? parent.width : 600

    function locate(p) {
        for (let i = 0; i < rep.count; i++) {
            const col = rep.itemAt(i);
            const q = col.mapFromItem(root, p.x, p.y);
            if (q.x >= 0 && q.x <= col.width && q.y >= -Theme.u * 10 && q.y <= col.height + Theme.u * 10) {
                let idx = 0;
                const chips = col.chips;
                for (let k = 0; k < chips.length; k++) {
                    const c = chips[k];
                    const cy = c.mapToItem(col, 0, c.height / 2).y;
                    if (q.y > cy)
                        idx = k + 1;
                }
                return [col.colId, idx];
            }
        }
        return ["", -1];
    }

    Row {
        id: row
        spacing: Theme.u * 4
        Repeater {
            id: rep
            model: root.columns
            PxBox {
                id: colBox
                required property var modelData
                readonly property string colId: modelData.id
                readonly property var ids: root.listFor(colId)
                property var chips: []
                width: (root.width - Theme.u * 12) / 4
                height: Math.max(Theme.u * 90, list.implicitHeight + head.height + Theme.u * 14)
                sunken: true
                color: root.dropCol === colId ? Theme.mix(Theme.sunken, Theme.accent, 0.18) : Qt.alpha(Theme.sunken, colId === "hidden" ? 0.4 : 0.75)

                PxText {
                    id: head
                    x: Theme.u * 3
                    y: Theme.u * 2
                    text: colBox.modelData.label
                    kind: "title"
                    color: colBox.colId === "hidden" ? Theme.textDim : (Theme.dark ? Theme.accent : Theme.edge)
                }

                Column {
                    id: list
                    x: Theme.u * 2
                    y: head.height + Theme.u * 5
                    width: parent.width - Theme.u * 8
                    spacing: Theme.u * 2

                    Repeater {
                        model: colBox.ids
                        onItemAdded: (i, it) => colBox.chips = Array.from({
                                "length": count
                            }, (_, k) => itemAt(k)).filter(x => x)
                        onItemRemoved: (i, it) => Qt.callLater(() => colBox.chips = Array.from({
                                    "length": count
                                }, (_, k) => itemAt(k)).filter(x => x && x !== it))
                        Item {
                            id: chip
                            required property string modelData
                            required property int index
                            readonly property var info: BarLayout.info(modelData)
                            // the eye: off = on the bar, on = hidden but still in its lane
                            readonly property bool off: BarLayout.disabled.includes(modelData)
                            width: list.width
                            height: Theme.u * 15

                            // insertion marker
                            Rectangle {
                                visible: root.dragId !== "" && root.dropCol === colBox.colId && root.dropIndex === chip.index
                                y: -Theme.u * 2
                                width: parent.width
                                height: Theme.u
                                color: Theme.accent
                            }
                            PxBox {
                                anchors.fill: parent
                                opacity: root.dragId === chip.modelData ? 0.35 : chip.off ? 0.45 : 1
                                color: cm.containsMouse ? Theme.mix(Theme.face, Theme.accent, 0.15) : Theme.face
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.u * 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.u * 3
                                    PxText {
                                        text: "⋮⋮"
                                        dim: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    PxIcon {
                                        name: chip.info.icon
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    PxText {
                                        text: chip.info.label
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: chip.width - Theme.u * 44
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: cm
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: root.dragId !== "" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property point start
                                onPressed: m => start = Qt.point(m.x, m.y)
                                onPositionChanged: m => {
                                    if (!pressed)
                                        return;
                                    if (root.dragId === "" && Math.abs(m.x - start.x) + Math.abs(m.y - start.y) > Theme.u * 3)
                                        root.dragId = chip.modelData;
                                    if (root.dragId !== "") {
                                        root.dragPos = mapToItem(root, m.x, m.y);
                                        const t = root.locate(root.dragPos);
                                        root.dropCol = t[0];
                                        root.dropIndex = t[1];
                                    }
                                }
                                onReleased: {
                                    if (root.dragId !== "" && root.dropCol !== "") {
                                        // indices in the source column shift once the chip is taken out
                                        let idx = root.dropIndex;
                                        if (root.dropCol === colBox.colId && idx > chip.index)
                                            idx--;
                                        BarLayout.move(root.dragId, root.dropCol, idx);
                                    }
                                    root.dragId = "";
                                    root.dropCol = "";
                                    root.dropIndex = -1;
                                }
                            }
                            // the eye: hide the widget on the bar, keep its lane and place
                            Item {
                                visible: colBox.colId !== "hidden"
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.u * 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.u * 13
                                height: Theme.u * 13
                                PxIcon {
                                    anchors.centerIn: parent
                                    name: "eye"
                                    opacity: chip.off ? 0.3 : 1
                                }
                                Rectangle {
                                    visible: chip.off
                                    anchors.centerIn: parent
                                    width: parent.width * 0.8
                                    height: Math.max(1, Math.round(Theme.u / 2))
                                    color: Theme.danger
                                    rotation: -45
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: BarLayout.setEnabled(chip.modelData, chip.off)
                                }
                            }
                        }
                    }
                    // end-of-list marker
                    Rectangle {
                        visible: root.dragId !== "" && root.dropCol === colBox.colId && root.dropIndex === colBox.ids.length
                        width: parent.width
                        height: Theme.u
                        color: Theme.accent
                    }
                    PxText {
                        visible: colBox.ids.length === 0
                        text: I18n.t("перетащи сюда", "Drop here")
                        dim: true
                    }
                }
            }
        }
    }

    // the chip following the cursor
    PxBox {
        visible: root.dragId !== ""
        z: 100
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        width: Theme.u * 70
        height: Theme.u * 15
        color: Theme.accent
        shadow: true
        Row {
            anchors.centerIn: parent
            spacing: Theme.u * 3
            PxIcon {
                name: root.dragId ? BarLayout.info(root.dragId).icon : "heart"
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: root.dragId ? BarLayout.info(root.dragId).label : ""
                color: Theme.selectText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
