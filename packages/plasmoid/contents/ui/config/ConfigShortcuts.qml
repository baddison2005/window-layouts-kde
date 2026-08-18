/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasma5support as Plasma5Support

KCM.SimpleKCM {
    id: page

    property string cfg_customLayouts: "[]"
    property string cfg_customLayoutsDefault: "[]"
    // Plasma passes every cfg_* property declared by main.xml to every KCM
    // page. Declare the settings edited by ConfigLayouts as well, even though
    // this page only reads customLayouts, so loading this category never
    // produces a partial "settings not synced" state.
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
    property string cfg_groupOrder: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"window\"]"
    property string cfg_groupOrderDefault: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"window\"]"
    property string statusMessage: ""
    readonly property string helperPath: decodeURIComponent(
        Qt.resolvedUrl("../../tools/sync-shortcuts.sh").toString().replace(/^file:\/\//, ""),
    )

    implicitWidth: Kirigami.Units.gridUnit * 34
    implicitHeight: Kirigami.Units.gridUnit * 32

    function encodedArgument(value) {
        return encodeURIComponent(value).replace(/[!'()*]/g, character =>
            `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
    }

    function appendAction(actionId, label) {
        shortcutModel.append({ actionId, label, shortcutText: "" });
    }

    function rebuildActions() {
        shortcutModel.clear();
        const fixed = [
            ["WindowLayoutsLeftHalf", i18n("Left Half")],
            ["WindowLayoutsRightHalf", i18n("Right Half")],
            ["WindowLayoutsTopHalf", i18n("Top Half")],
            ["WindowLayoutsBottomHalf", i18n("Bottom Half")],
            ["WindowLayoutsTopLeft", i18n("Top Left")],
            ["WindowLayoutsTopRight", i18n("Top Right")],
            ["WindowLayoutsBottomLeft", i18n("Bottom Left")],
            ["WindowLayoutsBottomRight", i18n("Bottom Right")],
            ["WindowLayoutsLeftThird", i18n("Left Third")],
            ["WindowLayoutsCenterThird", i18n("Center Third")],
            ["WindowLayoutsRightThird", i18n("Right Third")],
            ["WindowLayoutsLeftTwoThirds", i18n("Left Two Thirds")],
            ["WindowLayoutsCenterTwoThirds", i18n("Center Two Thirds")],
            ["WindowLayoutsRightTwoThirds", i18n("Right Two Thirds")],
            ["WindowLayoutsMaximize", i18n("Maximize")],
            ["WindowLayoutsCenter", i18n("Center")],
            ["WindowLayoutsRestore", i18n("Restore")],
            ["WindowLayoutsPreviousWorkspace", i18n("Move to Previous Workspace")],
            ["WindowLayoutsNextWorkspace", i18n("Move to Next Workspace")],
            ["WindowLayoutsPreviousMonitor", i18n("Move to Previous Monitor")],
            ["WindowLayoutsNextMonitor", i18n("Move to Next Monitor")],
        ];
        fixed.forEach(action => appendAction(action[0], action[1]));

        let custom = [];
        try {
            const parsed = JSON.parse(cfg_customLayouts || "[]");
            if (Array.isArray(parsed)) {
                custom = parsed.slice(0, 20);
            }
        } catch (error) {
            custom = [];
        }
        const usedSlots = [];
        custom.forEach((layout, index) => {
            if (!layout || typeof layout.name !== "string") {
                return;
            }
            let slot = Number.isInteger(layout.shortcutSlot)
                && layout.shortcutSlot >= 1
                && layout.shortcutSlot <= 20
                && usedSlots.indexOf(layout.shortcutSlot) < 0
                    ? layout.shortcutSlot
                    : -1;
            if (slot < 0) {
                for (let candidate = 1; candidate <= 20; candidate += 1) {
                    if (usedSlots.indexOf(candidate) < 0) {
                        slot = candidate;
                        break;
                    }
                }
            }
            usedSlots.push(slot);
            appendAction(
                `WindowLayoutsCustom${slot}`,
                layout.name.trim() || i18n("Custom Layout %1", index + 1),
            );
        });
        shortcutRunner.connectSource(`${helperPath} get`);
    }

    function setShortcut(actionId, shortcutText) {
        statusMessage = i18n("Saving shortcut…");
        shortcutRunner.connectSource(
            `${helperPath} set ${encodedArgument(actionId)} ${encodedArgument(shortcutText)}`,
        );
    }

    Component.onCompleted: rebuildActions()
    onCfg_customLayoutsChanged: rebuildActions()

    ListModel { id: shortcutModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: text.length > 0
            text: page.statusMessage
            type: text.startsWith(i18n("Could not"))
                ? Kirigami.MessageType.Error
                : Kirigami.MessageType.Information
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Assign or remove a global keyboard shortcut for each layout. KDE will warn before reassigning a shortcut that is already in use.")
            wrapMode: Text.WordWrap
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                model: shortcutModel
                spacing: Kirigami.Units.smallSpacing

                delegate: QQC2.ItemDelegate {
                    required property int index
                    required property string actionId
                    required property string label
                    required property string shortcutText

                    width: ListView.view.width
                    hoverEnabled: false

                    contentItem: RowLayout {
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: label
                            elide: Text.ElideRight
                        }

                        KQuickControls.KeySequenceItem {
                            keySequence: shortcutText
                            showClearButton: true
                            multiKeyShortcutsAllowed: false
                            onKeySequenceModified: {
                                const text = String(keySequence);
                                shortcutModel.setProperty(index, "shortcutText", text);
                                page.setShortcut(actionId, text);
                            }
                        }
                    }
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: shortcutRunner
        engine: "executable"

        onNewData: function(sourceName, data) {
            const exitCode = data["exit code"];
            if (exitCode !== undefined && exitCode !== 0) {
                page.statusMessage = i18n("Could not update shortcuts: %1", data.stderr || i18n("unknown error"));
                disconnectSource(sourceName);
                return;
            }
            try {
                const values = JSON.parse((data.stdout || "{}").trim());
                if (sourceName.endsWith(" get")) {
                    for (let index = 0; index < shortcutModel.count; index += 1) {
                        const actionId = shortcutModel.get(index).actionId;
                        shortcutModel.setProperty(index, "shortcutText", values[actionId] || "");
                    }
                    page.statusMessage = "";
                } else if (values.changed) {
                    page.statusMessage = i18n("Shortcut saved.");
                } else {
                    page.statusMessage = i18n("Could not update shortcuts: %1", values.error || i18n("KDE rejected the shortcut"));
                }
            } catch (error) {
                page.statusMessage = i18n("Could not read the shortcut service response.");
            }
            disconnectSource(sourceName);
        }
    }
}
