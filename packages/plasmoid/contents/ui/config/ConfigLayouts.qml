/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    property string cfg_customLayouts: "[]"
    property string cfg_customLayoutsDefault: "[]"
    property bool cfg_floatingButtonEnabled: false
    property bool cfg_floatingButtonEnabledDefault: false
    property bool cfg_dragTargetsEnabled: false
    property bool cfg_dragTargetsEnabledDefault: false
    property bool cfg_showAllDragTargets: false
    property bool cfg_showAllDragTargetsDefault: false
    property string cfg_floatingButtonSize: "default"
    property string cfg_floatingButtonSizeDefault: "default"
    property string cfg_groupOrder: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"window\"]"
    property string cfg_groupOrderDefault: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"window\"]"
    readonly property var floatingButtonSizes: ["small", "default", "big", "extraBig"]
    readonly property var groupIds: ["halves", "quarters", "thirds", "twoThirds", "custom", "window"]

    readonly property int gridColumns: 24
    readonly property int gridRows: 12
    property int selectedIndex: -1
    property int modelRevision: 0
    property bool initialized: false
    property bool loadingConfiguration: false
    property bool updatingConfiguration: false
    property bool loadingGroupOrder: false
    property bool updatingGroupOrder: false
    property int selectedGroupIndex: 0

    implicitWidth: Kirigami.Units.gridUnit * 43
    implicitHeight: Kirigami.Units.gridUnit * 44

    function floatingButtonSizeIndex() {
        const index = floatingButtonSizes.indexOf(cfg_floatingButtonSize);
        return index >= 0 ? index : 1;
    }

    function groupLabel(groupId) {
        switch (groupId) {
        case "halves": return i18n("Halves");
        case "quarters": return i18n("Quarters");
        case "thirds": return i18n("Thirds");
        case "twoThirds": return i18n("Two Thirds");
        case "custom": return i18n("Custom");
        case "window": return i18n("Window");
        default: return groupId;
        }
    }

    function loadGroupOrder() {
        // Keep this model separate from customLayoutModel: group ordering has
        // no geometry and must remain reversible through the KCM's Cancel.
        loadingGroupOrder = true;
        groupOrderModel.clear();

        let stored = [];
        try {
            const parsed = JSON.parse(cfg_groupOrder || "[]");
            if (Array.isArray(parsed)) {
                stored = parsed;
            }
        } catch (error) {
            stored = [];
        }

        const validated = [];
        for (let index = 0; index < stored.length; index += 1) {
            const groupId = stored[index];
            if (groupIds.indexOf(groupId) >= 0 && validated.indexOf(groupId) < 0) {
                validated.push(groupId);
            }
        }
        for (let index = 0; index < groupIds.length; index += 1) {
            if (validated.indexOf(groupIds[index]) < 0) {
                validated.push(groupIds[index]);
            }
        }
        for (let index = 0; index < validated.length; index += 1) {
            groupOrderModel.append({
                groupId: validated[index],
                groupName: groupLabel(validated[index]),
            });
        }
        selectedGroupIndex = groupOrderModel.count > 0 ? 0 : -1;
        loadingGroupOrder = false;
    }

    function storeGroupOrder() {
        if (!initialized || loadingGroupOrder) {
            return;
        }
        const order = [];
        for (let index = 0; index < groupOrderModel.count; index += 1) {
            order.push(groupOrderModel.get(index).groupId);
        }
        // Only cfg_groupOrder is changed here. Plasma persists it on Apply or
        // OK, then main.qml forwards the committed value to the shared store.
        updatingGroupOrder = true;
        cfg_groupOrder = JSON.stringify(order);
        updatingGroupOrder = false;
    }

    function moveSelectedGroup(offset) {
        const targetIndex = selectedGroupIndex + offset;
        if (selectedGroupIndex < 0
                || targetIndex < 0
                || targetIndex >= groupOrderModel.count) {
            return;
        }
        groupOrderModel.move(selectedGroupIndex, targetIndex, 1);
        selectedGroupIndex = targetIndex;
        storeGroupOrder();
    }

    function updateConfigurationWindowTitle() {
        const configurationWindow = page.Window.window;
        if (configurationWindow) {
            configurationWindow.title = i18n("Configure Window Layouts");
        }
    }

    function roundedFraction(value, total) {
        return Number((value / total).toFixed(6));
    }

    function selectedLayout() {
        // Referencing the revision makes bindings refresh after ListModel role
        // changes made through setProperty().
        const revision = modelRevision;
        return selectedIndex >= 0 && selectedIndex < customLayoutModel.count
            ? customLayoutModel.get(selectedIndex)
            : null;
    }

    function validStoredLayout(candidate) {
        return candidate
            && typeof candidate.name === "string"
            && Number.isFinite(candidate.x)
            && Number.isFinite(candidate.y)
            && Number.isFinite(candidate.width)
            && Number.isFinite(candidate.height)
            && candidate.x >= 0
            && candidate.y >= 0
            && candidate.width > 0
            && candidate.height > 0
            && candidate.x + candidate.width <= 1.000001
            && candidate.y + candidate.height <= 1.000001;
    }

    function loadLayouts() {
        loadingConfiguration = true;
        customLayoutModel.clear();

        let parsed = [];
        try {
            const candidate = JSON.parse(cfg_customLayouts || "[]");
            if (Array.isArray(candidate)) {
                parsed = candidate;
            }
        } catch (error) {
            parsed = [];
        }

        for (let index = 0; index < Math.min(parsed.length, 20); index += 1) {
            const layout = parsed[index];
            if (!validStoredLayout(layout)) {
                continue;
            }

            const column = Math.max(0, Math.min(gridColumns - 1, Math.round(layout.x * gridColumns)));
            const row = Math.max(0, Math.min(gridRows - 1, Math.round(layout.y * gridRows)));
            const columnSpan = Math.max(1, Math.min(gridColumns - column, Math.round(layout.width * gridColumns)));
            const rowSpan = Math.max(1, Math.min(gridRows - row, Math.round(layout.height * gridRows)));

            customLayoutModel.append({
                layoutName: layout.name.trim() || i18n("Custom Layout %1", index + 1),
                column,
                row,
                columnSpan,
                rowSpan,
            });
        }

        selectedIndex = customLayoutModel.count > 0 ? 0 : -1;
        modelRevision += 1;
        loadingConfiguration = false;
        updateNameEditor();
    }

    function storeLayouts() {
        if (!initialized || loadingConfiguration) {
            return;
        }

        const layouts = [];
        for (let index = 0; index < customLayoutModel.count; index += 1) {
            const layout = customLayoutModel.get(index);
            layouts.push({
                name: layout.layoutName.trim() || i18n("Custom Layout %1", index + 1),
                x: roundedFraction(layout.column, gridColumns),
                y: roundedFraction(layout.row, gridRows),
                width: roundedFraction(layout.columnSpan, gridColumns),
                height: roundedFraction(layout.rowSpan, gridRows),
            });
        }

        updatingConfiguration = true;
        cfg_customLayouts = JSON.stringify(layouts);
        updatingConfiguration = false;
    }

    function updateNameEditor() {
        const layout = selectedLayout();
        nameEditor.text = layout ? layout.layoutName : "";
    }

    function chooseLayout(index) {
        selectedIndex = index;
        updateNameEditor();
    }

    function addLayout() {
        if (customLayoutModel.count >= 20) {
            return;
        }

        customLayoutModel.append({
            layoutName: i18n("Custom Layout %1", customLayoutModel.count + 1),
            column: 0,
            row: 0,
            columnSpan: Math.round(gridColumns / 2),
            rowSpan: Math.round(gridRows / 2),
        });
        modelRevision += 1;
        chooseLayout(customLayoutModel.count - 1);
        storeLayouts();
    }

    function removeSelectedLayout() {
        if (selectedIndex < 0) {
            return;
        }

        const removedIndex = selectedIndex;
        customLayoutModel.remove(removedIndex);
        selectedIndex = customLayoutModel.count === 0
            ? -1
            : Math.min(removedIndex, customLayoutModel.count - 1);
        modelRevision += 1;
        updateNameEditor();
        storeLayouts();
    }

    function moveSelectedLayout(offset) {
        if (selectedIndex < 0) {
            return;
        }

        const targetIndex = selectedIndex + offset;
        if (targetIndex < 0 || targetIndex >= customLayoutModel.count) {
            return;
        }

        customLayoutModel.move(selectedIndex, targetIndex, 1);
        selectedIndex = targetIndex;
        modelRevision += 1;
        updateNameEditor();
        storeLayouts();
    }

    function setSelection(firstColumn, firstRow, lastColumn, lastRow) {
        if (selectedIndex < 0) {
            return;
        }

        const left = Math.min(firstColumn, lastColumn);
        const top = Math.min(firstRow, lastRow);
        const right = Math.max(firstColumn, lastColumn);
        const bottom = Math.max(firstRow, lastRow);
        customLayoutModel.setProperty(selectedIndex, "column", left);
        customLayoutModel.setProperty(selectedIndex, "row", top);
        customLayoutModel.setProperty(selectedIndex, "columnSpan", right - left + 1);
        customLayoutModel.setProperty(selectedIndex, "rowSpan", bottom - top + 1);
        modelRevision += 1;
    }

    onCfg_customLayoutsChanged: {
        if (initialized && !updatingConfiguration) {
            loadLayouts();
        }
    }

    onCfg_groupOrderChanged: {
        if (initialized && !updatingGroupOrder) {
            loadGroupOrder();
        }
    }

    Component.onCompleted: {
        initialized = true;
        loadLayouts();
        loadGroupOrder();
        Qt.callLater(page.updateConfigurationWindowTitle);
    }

    ListModel {
        id: customLayoutModel
    }

    ListModel {
        id: groupOrderModel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 12
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Saved layouts")
                font.bold: true
            }

            QQC2.Frame {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    anchors.fill: parent
                    clip: true
                    model: customLayoutModel
                    spacing: Kirigami.Units.smallSpacing

                    delegate: QQC2.ItemDelegate {
                        required property int index
                        required property string layoutName

                        width: ListView.view.width
                        text: layoutName
                        highlighted: page.selectedIndex === index
                        onClicked: page.chooseLayout(index)
                    }

                    QQC2.Label {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.largeSpacing * 2
                        visible: customLayoutModel.count === 0
                        text: i18n("No custom layouts yet.\nSelect Add to create one.")
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.disabledTextColor
                        wrapMode: Text.WordWrap
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.Button {
                    Layout.fillWidth: true
                    text: i18n("Add")
                    icon.name: "list-add"
                    enabled: customLayoutModel.count < 20
                    onClicked: page.addLayout()
                }

                QQC2.Button {
                    text: i18n("Remove")
                    icon.name: "edit-delete"
                    enabled: page.selectedIndex >= 0
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: page.removeSelectedLayout()
                }
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.Button {
                    Layout.fillWidth: true
                    text: i18n("Move Up")
                    icon.name: "go-up"
                    enabled: page.selectedIndex > 0
                    onClicked: page.moveSelectedLayout(-1)
                }

                QQC2.Button {
                    Layout.fillWidth: true
                    text: i18n("Move Down")
                    icon.name: "go-down"
                    enabled: page.selectedIndex >= 0
                        && page.selectedIndex < customLayoutModel.count - 1
                    onClicked: page.moveSelectedLayout(1)
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18np("%1 of 20 layout", "%1 of 20 layouts", customLayoutModel.count)
                color: Kirigami.Theme.disabledTextColor
            }
        }

        ColumnLayout {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 24
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Name")
                font.bold: true
            }

            QQC2.TextField {
                id: nameEditor

                Layout.fillWidth: true
                enabled: page.selectedIndex >= 0
                placeholderText: i18n("Layout name")
                maximumLength: 80

                onTextEdited: {
                    if (page.selectedIndex >= 0) {
                        customLayoutModel.setProperty(page.selectedIndex, "layoutName", text);
                        page.modelRevision += 1;
                        page.storeLayouts();
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Drag across the grid to choose the window's position and size.")
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
            }

            Rectangle {
                id: screenPreview

                property int dragStartColumn: 0
                property int dragStartRow: 0

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 15
                color: Kirigami.Theme.backgroundColor
                border.color: Kirigami.Theme.textColor
                border.width: 2
                radius: Kirigami.Units.cornerRadius
                opacity: page.selectedIndex >= 0 ? 1 : 0.45

                Repeater {
                    model: page.gridColumns * page.gridRows

                    delegate: Rectangle {
                        id: gridCell

                        required property int index
                        readonly property int cellColumn: index % page.gridColumns
                        readonly property int cellRow: Math.floor(index / page.gridColumns)
                        readonly property bool selectedCell: {
                            const revision = page.modelRevision;
                            const layout = page.selectedLayout();
                            return layout
                                && cellColumn >= layout.column
                                && cellColumn < layout.column + layout.columnSpan
                                && cellRow >= layout.row
                                && cellRow < layout.row + layout.rowSpan;
                        }

                        x: Math.round(cellColumn * screenPreview.width / page.gridColumns)
                        y: Math.round(cellRow * screenPreview.height / page.gridRows)
                        width: Math.ceil(screenPreview.width / page.gridColumns)
                        height: Math.ceil(screenPreview.height / page.gridRows)
                        color: selectedCell ? Kirigami.Theme.highlightColor : "transparent"
                        border.color: selectedCell
                            ? Kirigami.Theme.highlightedTextColor
                            : Kirigami.Theme.disabledTextColor
                        border.width: 1
                        opacity: selectedCell ? 0.78 : 0.45
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: page.selectedIndex >= 0
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    cursorShape: Qt.CrossCursor

                    function columnAt(position) {
                        return Math.max(0, Math.min(page.gridColumns - 1,
                            Math.floor(position / width * page.gridColumns)));
                    }

                    function rowAt(position) {
                        return Math.max(0, Math.min(page.gridRows - 1,
                            Math.floor(position / height * page.gridRows)));
                    }

                    onPressed: function(mouse) {
                        mouse.accepted = true;
                        screenPreview.dragStartColumn = columnAt(mouse.x);
                        screenPreview.dragStartRow = rowAt(mouse.y);
                        page.setSelection(
                            screenPreview.dragStartColumn,
                            screenPreview.dragStartRow,
                            screenPreview.dragStartColumn,
                            screenPreview.dragStartRow,
                        );
                    }

                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            page.setSelection(
                                screenPreview.dragStartColumn,
                                screenPreview.dragStartRow,
                                columnAt(mouse.x),
                                rowAt(mouse.y),
                            );
                        }
                    }

                    onReleased: page.storeLayouts()
                    onCanceled: page.storeLayouts()
                }

                QQC2.Label {
                    anchors.centerIn: parent
                    visible: page.selectedIndex < 0
                    text: i18n("Add or select a layout")
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: {
                    const revision = page.modelRevision;
                    const layout = page.selectedLayout();
                    if (!layout) {
                        return i18n("No layout selected");
                    }
                    return i18n(
                        "Position: %1%, %2% · Size: %3% × %4%",
                        Math.round(layout.column / page.gridColumns * 100),
                        Math.round(layout.row / page.gridRows * 100),
                        Math.round(layout.columnSpan / page.gridColumns * 100),
                        Math.round(layout.rowSpan / page.gridRows * 100),
                    );
                }
                color: Kirigami.Theme.disabledTextColor
            }
        }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 11
            spacing: Kirigami.Units.largeSpacing

            QQC2.GroupBox {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 17
                Layout.fillHeight: true
                title: i18n("Layout group order")

                RowLayout {
                    anchors.fill: parent

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: groupOrderModel

                        delegate: QQC2.ItemDelegate {
                            required property int index
                            required property string groupName

                            width: ListView.view.width
                            text: groupName
                            highlighted: page.selectedGroupIndex === index
                            onClicked: page.selectedGroupIndex = index
                        }
                    }

                    ColumnLayout {
                        QQC2.Button {
                            icon.name: "go-up"
                            text: i18n("Move Up")
                            display: QQC2.AbstractButton.IconOnly
                            enabled: page.selectedGroupIndex > 0
                            onClicked: page.moveSelectedGroup(-1)
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                        }

                        QQC2.Button {
                            icon.name: "go-down"
                            text: i18n("Move Down")
                            display: QQC2.AbstractButton.IconOnly
                            enabled: page.selectedGroupIndex >= 0
                                && page.selectedGroupIndex < groupOrderModel.count - 1
                            onClicked: page.moveSelectedGroup(1)
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            QQC2.GroupBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: i18n("Features")

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                QQC2.Switch {
                    Layout.fillWidth: true
                    text: i18n("Show floating button beside the active window")
                    checked: page.cfg_floatingButtonEnabled
                    onToggled: page.cfg_floatingButtonEnabled = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    enabled: page.cfg_floatingButtonEnabled

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: i18n("Floating button size")
                    }

                    QQC2.ComboBox {
                        model: [i18n("Small"), i18n("Default"), i18n("Big"), i18n("Extra big")]
                        currentIndex: page.floatingButtonSizeIndex()
                        onActivated: index => {
                            page.cfg_floatingButtonSize = page.floatingButtonSizes[index];
                        }
                    }
                }

                QQC2.Switch {
                    Layout.fillWidth: true
                    text: i18n("Show layout targets while dragging a window")
                    checked: page.cfg_dragTargetsEnabled
                    onToggled: page.cfg_dragTargetsEnabled = checked
                }

                QQC2.Switch {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    text: i18n("Show all layout targets immediately")
                    enabled: page.cfg_dragTargetsEnabled
                    checked: page.cfg_showAllDragTargets
                    onToggled: page.cfg_showAllDragTargets = checked
                }
            }
        }
        }
    }
}
