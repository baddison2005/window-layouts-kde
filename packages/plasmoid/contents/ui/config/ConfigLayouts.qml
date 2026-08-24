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
    property string cfg_customGroups: "[]"
    property string cfg_customGroupsDefault: "[]"
    property bool cfg_floatingButtonEnabled: false
    property bool cfg_floatingButtonEnabledDefault: false
    property bool cfg_dragTargetsEnabled: false
    property bool cfg_dragTargetsEnabledDefault: false
    property bool cfg_showAllDragTargets: false
    property bool cfg_showAllDragTargetsDefault: false
    property string cfg_dragTargetPlacement: "zones"
    property string cfg_dragTargetPlacementDefault: "zones"
    property bool cfg_showAllTopDragTargets: false
    property bool cfg_showAllTopDragTargetsDefault: false
    property string cfg_floatingButtonSize: "default"
    property string cfg_floatingButtonSizeDefault: "default"
    property int cfg_layoutPadding: 0
    property int cfg_layoutPaddingDefault: 0
    property string cfg_groupOrder: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"fillDisplay\",\"window\"]"
    property string cfg_groupOrderDefault: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"fillDisplay\",\"window\"]"
    readonly property var floatingButtonSizes: ["small", "default", "big", "extraBig"]
    readonly property var groupIds: ["halves", "quarters", "thirds", "twoThirds", "custom", "fillDisplay", "window"]

    readonly property int gridColumns: 24
    readonly property int gridRows: 12
    property int selectedIndex: -1
    property int modelRevision: 0
    property bool initialized: false
    property bool loadingConfiguration: false
    property bool updatingConfiguration: false
    property bool loadingCustomGroups: false
    property bool updatingCustomGroups: false
    property bool loadingGroupOrder: false
    property bool updatingGroupOrder: false
    property int selectedGroupIndex: 0

    implicitWidth: Kirigami.Units.gridUnit * 43
    implicitHeight: Kirigami.Units.gridUnit * 49

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
        case "fillDisplay": return i18n("Fill Display");
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
        if (validated.indexOf("fillDisplay") < 0) {
            const windowIndex = validated.indexOf("window");
            validated.splice(
                windowIndex >= 0 ? windowIndex : validated.length,
                0,
                "fillDisplay",
            );
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

    function customGroupName(groupId) {
        if (!groupId) {
            return i18n("Unassigned");
        }
        for (let index = 0; index < customGroupModel.count; index += 1) {
            const group = customGroupModel.get(index);
            if (group.groupId === groupId) {
                return group.groupName;
            }
        }
        return i18n("Unassigned");
    }

    function appendSavedLayoutGroup(groupId, groupName) {
        let headingAdded = false;
        for (let index = 0; index < customLayoutModel.count; index += 1) {
            const layout = customLayoutModel.get(index);
            if (layout.customGroupId !== groupId) {
                continue;
            }
            if (!headingAdded) {
                savedLayoutModel.append({
                    rowKind: "heading",
                    rowLabel: groupName,
                    layoutIndex: -1,
                });
                headingAdded = true;
            }
            savedLayoutModel.append({
                rowKind: "layout",
                rowLabel: layout.layoutName,
                layoutIndex: index,
            });
        }
    }

    function rebuildSavedLayoutModel() {
        savedLayoutModel.clear();
        // Preserve the user's custom-group order. Unassigned layouts are kept
        // together at the end so group membership is visible at a glance.
        for (let index = 0; index < customGroupModel.count; index += 1) {
            const group = customGroupModel.get(index);
            appendSavedLayoutGroup(group.groupId, group.groupName);
        }
        appendSavedLayoutGroup("", i18n("Unassigned"));
    }

    function adjacentLayoutIndex(offset) {
        if (selectedIndex < 0 || selectedIndex >= customLayoutModel.count) {
            return -1;
        }
        const groupId = customLayoutModel.get(selectedIndex).customGroupId;
        for (let index = selectedIndex + offset;
                index >= 0 && index < customLayoutModel.count;
                index += offset) {
            if (customLayoutModel.get(index).customGroupId === groupId) {
                return index;
            }
        }
        return -1;
    }

    function canMoveSelectedLayout(offset) {
        const revision = modelRevision;
        return adjacentLayoutIndex(offset) >= 0;
    }

    function validCustomGroupId(groupId) {
        if (!groupId) {
            return "";
        }
        for (let index = 0; index < customGroupModel.count; index += 1) {
            if (customGroupModel.get(index).groupId === groupId) {
                return groupId;
            }
        }
        return "";
    }

    function rebuildCustomGroupChoices() {
        customGroupChoiceModel.clear();
        customGroupChoiceModel.append({ groupId: "", groupName: i18n("Unassigned") });
        for (let index = 0; index < customGroupModel.count; index += 1) {
            const group = customGroupModel.get(index);
            customGroupChoiceModel.append({ groupId: group.groupId, groupName: group.groupName });
        }
        updateGroupEditor();
    }

    function loadCustomGroups() {
        loadingCustomGroups = true;
        customGroupModel.clear();
        let parsed = [];
        try {
            const candidate = JSON.parse(cfg_customGroups || "[]");
            if (Array.isArray(candidate)) {
                parsed = candidate;
            }
        } catch (error) {
            parsed = [];
        }
        const usedIds = [];
        const usedSlots = [];
        for (let index = 0; index < parsed.length; index += 1) {
            const group = parsed[index];
            if (group
                    && typeof group.id === "string"
                    && group.id.length > 0
                    && usedIds.indexOf(group.id) < 0
                    && typeof group.name === "string"
                    && group.name.trim().length > 0) {
                let fillShortcutSlot = Number.isInteger(group.fillShortcutSlot)
                    && group.fillShortcutSlot >= 1
                    && group.fillShortcutSlot <= 20
                    && usedSlots.indexOf(group.fillShortcutSlot) < 0
                        ? group.fillShortcutSlot
                        : -1;
                if (fillShortcutSlot < 0) {
                    for (let slot = 1; slot <= 20; slot += 1) {
                        if (usedSlots.indexOf(slot) < 0) {
                            fillShortcutSlot = slot;
                            break;
                        }
                    }
                }
                customGroupModel.append({
                    groupId: group.id,
                    groupName: group.name.trim(),
                    fillShortcutSlot,
                });
                usedIds.push(group.id);
                usedSlots.push(fillShortcutSlot);
            }
        }
        loadingCustomGroups = false;
        rebuildCustomGroupChoices();
    }

    function storeCustomGroups() {
        if (!initialized || loadingCustomGroups) {
            return;
        }
        const groups = [];
        for (let index = 0; index < customGroupModel.count; index += 1) {
            const group = customGroupModel.get(index);
            groups.push({
                id: group.groupId,
                name: group.groupName,
                fillShortcutSlot: group.fillShortcutSlot,
            });
        }
        updatingCustomGroups = true;
        cfg_customGroups = JSON.stringify(groups);
        updatingCustomGroups = false;
    }

    function nextShortcutSlot() {
        const used = [];
        for (let index = 0; index < customLayoutModel.count; index += 1) {
            used.push(customLayoutModel.get(index).shortcutSlot);
        }
        for (let slot = 1; slot <= 20; slot += 1) {
            if (used.indexOf(slot) < 0) {
                return slot;
            }
        }
        return 1;
    }

    function nextFillShortcutSlot() {
        const used = [];
        for (let index = 0; index < customGroupModel.count; index += 1) {
            used.push(customGroupModel.get(index).fillShortcutSlot);
        }
        for (let slot = 1; slot <= 20; slot += 1) {
            if (used.indexOf(slot) < 0) {
                return slot;
            }
        }
        return 1;
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

        const usedSlots = [];
        for (let index = 0; index < Math.min(parsed.length, 20); index += 1) {
            const layout = parsed[index];
            if (!validStoredLayout(layout)) {
                continue;
            }

            const column = Math.max(0, Math.min(gridColumns - 1, Math.round(layout.x * gridColumns)));
            const row = Math.max(0, Math.min(gridRows - 1, Math.round(layout.y * gridRows)));
            const columnSpan = Math.max(1, Math.min(gridColumns - column, Math.round(layout.width * gridColumns)));
            const rowSpan = Math.max(1, Math.min(gridRows - row, Math.round(layout.height * gridRows)));

            let shortcutSlot = Number.isInteger(layout.shortcutSlot)
                && layout.shortcutSlot >= 1
                && layout.shortcutSlot <= 20
                && usedSlots.indexOf(layout.shortcutSlot) < 0
                    ? layout.shortcutSlot
                    : -1;
            if (shortcutSlot < 0) {
                for (let slot = 1; slot <= 20; slot += 1) {
                    if (usedSlots.indexOf(slot) < 0) {
                        shortcutSlot = slot;
                        break;
                    }
                }
            }
            usedSlots.push(shortcutSlot);
            customLayoutModel.append({
                layoutName: layout.name.trim() || i18n("Custom Layout %1", index + 1),
                column,
                row,
                columnSpan,
                rowSpan,
                shortcutSlot,
                customGroupId: validCustomGroupId(layout.groupId),
            });
        }

        selectedIndex = customLayoutModel.count > 0 ? 0 : -1;
        modelRevision += 1;
        loadingConfiguration = false;
        rebuildSavedLayoutModel();
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
                shortcutSlot: layout.shortcutSlot,
                groupId: layout.customGroupId,
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

    function updateGroupEditor() {
        if (!groupEditor) {
            return;
        }
        const layout = selectedLayout();
        const groupId = layout ? layout.customGroupId : "";
        let selected = 0;
        for (let index = 0; index < customGroupChoiceModel.count; index += 1) {
            if (customGroupChoiceModel.get(index).groupId === groupId) {
                selected = index;
                break;
            }
        }
        groupEditor.currentIndex = selected;
    }

    function chooseLayout(index) {
        selectedIndex = index;
        updateNameEditor();
        updateGroupEditor();
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
            shortcutSlot: nextShortcutSlot(),
            customGroupId: "",
        });
        modelRevision += 1;
        rebuildSavedLayoutModel();
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
        rebuildSavedLayoutModel();
        updateNameEditor();
        updateGroupEditor();
        storeLayouts();
    }

    function moveSelectedLayout(offset) {
        if (selectedIndex < 0) {
            return;
        }

        const targetIndex = adjacentLayoutIndex(offset);
        if (targetIndex < 0) {
            return;
        }

        customLayoutModel.move(selectedIndex, targetIndex, 1);
        selectedIndex = targetIndex;
        modelRevision += 1;
        rebuildSavedLayoutModel();
        updateNameEditor();
        updateGroupEditor();
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

    function createCustomGroup(name) {
        const trimmedName = name.trim();
        if (!trimmedName) {
            return;
        }
        const groupId = `group-${Date.now().toString(36)}-${customGroupModel.count + 1}`;
        customGroupModel.append({
            groupId,
            groupName: trimmedName,
            fillShortcutSlot: nextFillShortcutSlot(),
        });
        storeCustomGroups();
        rebuildCustomGroupChoices();
        if (selectedIndex >= 0) {
            customLayoutModel.setProperty(selectedIndex, "customGroupId", groupId);
            modelRevision += 1;
            rebuildSavedLayoutModel();
            updateGroupEditor();
            storeLayouts();
        }
    }

    function renameCurrentCustomGroup(name) {
        const choice = groupEditor.currentIndex >= 0
            ? customGroupChoiceModel.get(groupEditor.currentIndex)
            : null;
        const trimmedName = name.trim();
        if (!choice || !choice.groupId || !trimmedName) {
            return;
        }
        for (let index = 0; index < customGroupModel.count; index += 1) {
            if (customGroupModel.get(index).groupId === choice.groupId) {
                customGroupModel.setProperty(index, "groupName", trimmedName);
                break;
            }
        }
        storeCustomGroups();
        rebuildCustomGroupChoices();
        rebuildSavedLayoutModel();
    }

    function removeCurrentCustomGroup() {
        const choice = groupEditor.currentIndex >= 0
            ? customGroupChoiceModel.get(groupEditor.currentIndex)
            : null;
        if (!choice || !choice.groupId) {
            return;
        }
        for (let index = customGroupModel.count - 1; index >= 0; index -= 1) {
            if (customGroupModel.get(index).groupId === choice.groupId) {
                customGroupModel.remove(index);
            }
        }
        for (let index = 0; index < customLayoutModel.count; index += 1) {
            if (customLayoutModel.get(index).customGroupId === choice.groupId) {
                customLayoutModel.setProperty(index, "customGroupId", "");
            }
        }
        modelRevision += 1;
        storeCustomGroups();
        rebuildCustomGroupChoices();
        rebuildSavedLayoutModel();
        storeLayouts();
    }

    onCfg_customLayoutsChanged: {
        if (initialized && !updatingConfiguration) {
            loadLayouts();
        }
    }

    onCfg_customGroupsChanged: {
        if (initialized && !updatingCustomGroups) {
            loadCustomGroups();
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
        loadCustomGroups();
        loadLayouts();
        loadGroupOrder();
        Qt.callLater(page.updateConfigurationWindowTitle);
    }

    ListModel {
        id: customLayoutModel
    }

    ListModel {
        id: savedLayoutModel
    }

    ListModel {
        id: groupOrderModel
    }

    ListModel {
        id: customGroupModel
    }

    ListModel {
        id: customGroupChoiceModel
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
                    model: savedLayoutModel

                    delegate: Item {
                        required property int index
                        required property string rowKind
                        required property string rowLabel
                        required property int layoutIndex

                        readonly property bool isLastLayoutInGroup:
                            rowKind === "layout"
                            && (index + 1 >= savedLayoutModel.count
                                || savedLayoutModel.get(index + 1).rowKind === "heading")
                        readonly property int layoutRowHeight:
                            Math.round(Kirigami.Units.gridUnit * 1.45)

                        width: ListView.view.width
                        height: rowKind === "heading"
                            ? groupHeading.implicitHeight + Kirigami.Units.smallSpacing
                            : layoutRowHeight
                                + (isLastLayoutInGroup
                                    ? Kirigami.Units.largeSpacing
                                    : 0)

                        QQC2.Label {
                            id: groupHeading

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.rowKind === "heading"
                            text: parent.rowLabel
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                            color: Kirigami.Theme.textColor
                            elide: Text.ElideRight
                        }

                        QQC2.ItemDelegate {
                            id: layoutDelegate

                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: parent.layoutRowHeight
                            visible: parent.rowKind === "layout"
                            leftPadding: Kirigami.Units.largeSpacing
                            text: parent.rowLabel
                            highlighted: page.selectedIndex === parent.layoutIndex
                            onClicked: page.chooseLayout(parent.layoutIndex)
                        }
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
                    enabled: page.canMoveSelectedLayout(-1)
                    onClicked: page.moveSelectedLayout(-1)
                }

                QQC2.Button {
                    Layout.fillWidth: true
                    text: i18n("Move Down")
                    icon.name: "go-down"
                    enabled: page.canMoveSelectedLayout(1)
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
                        page.rebuildSavedLayoutModel();
                        page.storeLayouts();
                    }
                }
            }

            QQC2.Label {
                text: i18n("Custom group")
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.ComboBox {
                    id: groupEditor

                    Layout.fillWidth: true
                    enabled: page.selectedIndex >= 0
                    model: customGroupChoiceModel
                    textRole: "groupName"
                    valueRole: "groupId"

                    onActivated: function(index) {
                        if (page.selectedIndex >= 0 && index >= 0) {
                            customLayoutModel.setProperty(
                                page.selectedIndex,
                                "customGroupId",
                                customGroupChoiceModel.get(index).groupId,
                            );
                            page.modelRevision += 1;
                            page.rebuildSavedLayoutModel();
                            page.storeLayouts();
                        }
                    }
                }

                QQC2.Button {
                    icon.name: "list-add"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Create group")
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: {
                        newGroupName.text = "";
                        newGroupDialog.open();
                        newGroupName.forceActiveFocus();
                    }
                }

                QQC2.Button {
                    icon.name: "document-edit"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Rename group")
                    enabled: groupEditor.currentIndex > 0
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: {
                        renameGroupName.text = groupEditor.currentText;
                        renameGroupDialog.open();
                        renameGroupName.forceActiveFocus();
                    }
                }

                QQC2.Button {
                    icon.name: "edit-delete"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Remove group")
                    enabled: groupEditor.currentIndex > 0
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: page.removeCurrentCustomGroup()
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
            Layout.preferredHeight: Kirigami.Units.gridUnit * 18
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

                RowLayout {
                    Layout.fillWidth: true

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: i18n("Layout padding (pixels)")
                    }

                    QQC2.SpinBox {
                        from: 0
                        to: 200
                        editable: true
                        value: page.cfg_layoutPadding
                        onValueModified: page.cfg_layoutPadding = value
                    }
                }

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

                QQC2.ButtonGroup {
                    id: targetPlacementGroup
                }

                QQC2.RadioButton {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    text: i18n("Layout targets at the center of each layout zone")
                    enabled: page.cfg_dragTargetsEnabled
                    checked: page.cfg_dragTargetPlacement === "zones"
                    QQC2.ButtonGroup.group: targetPlacementGroup
                    onToggled: {
                        if (checked) {
                            page.cfg_dragTargetPlacement = "zones";
                        }
                    }
                }

                QQC2.Switch {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 2
                    text: i18n("Display zone targets immediately")
                    enabled: page.cfg_dragTargetsEnabled
                        && page.cfg_dragTargetPlacement === "zones"
                    checked: page.cfg_showAllDragTargets
                    onToggled: page.cfg_showAllDragTargets = checked
                }

                QQC2.RadioButton {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    text: i18n("Layout targets in a top-center strip")
                    enabled: page.cfg_dragTargetsEnabled
                    checked: page.cfg_dragTargetPlacement === "top"
                    QQC2.ButtonGroup.group: targetPlacementGroup
                    onToggled: {
                        if (checked) {
                            page.cfg_dragTargetPlacement = "top";
                        }
                    }
                }

                QQC2.Switch {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 2
                    text: i18n("Display the top-center strip immediately")
                    enabled: page.cfg_dragTargetsEnabled
                        && page.cfg_dragTargetPlacement === "top"
                    checked: page.cfg_showAllTopDragTargets
                    onToggled: page.cfg_showAllTopDragTargets = checked
                }
            }
        }
        }
    }

    QQC2.Dialog {
        id: newGroupDialog

        anchors.centerIn: parent
        width: Math.min(
            page.width - Kirigami.Units.gridUnit * 2,
            Kirigami.Units.gridUnit * 26
        )
        title: i18n("Create Custom Group")
        modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: page.createCustomGroup(newGroupName.text)

        QQC2.TextField {
            id: newGroupName
            width: newGroupDialog.availableWidth
            placeholderText: i18n("Group name")
            maximumLength: 80
        }
    }

    QQC2.Dialog {
        id: renameGroupDialog

        anchors.centerIn: parent
        width: Math.min(
            page.width - Kirigami.Units.gridUnit * 2,
            Kirigami.Units.gridUnit * 26
        )
        title: i18n("Rename Custom Group")
        modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: page.renameCurrentCustomGroup(renameGroupName.text)

        QQC2.TextField {
            id: renameGroupName
            width: renameGroupDialog.availableWidth
            placeholderText: i18n("Group name")
            maximumLength: 80
        }
    }
}
