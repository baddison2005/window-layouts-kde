/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property string lastError: ""
    property string configuredLayoutsJson: Plasmoid.configuration.customLayouts || "[]"
    property bool configuredFloatingButtonEnabled: Plasmoid.configuration.floatingButtonEnabled
    property bool configuredDragTargetsEnabled: Plasmoid.configuration.dragTargetsEnabled
    property bool configuredShowAllDragTargets: Plasmoid.configuration.showAllDragTargets
    property string configuredFloatingButtonSize: Plasmoid.configuration.floatingButtonSize || "default"
    property string configuredGroupOrderJson: Plasmoid.configuration.groupOrder
        || "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"window\"]"
    property bool componentReady: false
    property int monitorCount: 1
    property int workspaceCount: 1
    readonly property string monitorQueryCommand: "kscreen-doctor -j"
    readonly property string workspaceQueryCommand: "qdbus-qt6 org.kde.KWin /VirtualDesktopManager "
        + "org.freedesktop.DBus.Properties.Get org.kde.KWin.VirtualDesktopManager count"

    Plasmoid.icon: Qt.resolvedUrl("../images/window-layouts.svg")
    Plasmoid.title: i18n("Window Layouts")
    toolTipMainText: i18n("Window Layouts")
    toolTipSubText: i18n("Move the active window to a saved position")

    // Desktop containments have a planar form factor. Panels are horizontal
    // or vertical and should always show the compact clickable icon.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation
        : compactRepresentation

    function addMenuItem(groupId, groupName, label, actionId, x, y, width, height, hasPreview, iconName, actionEnabled = true) {
        layoutModel.append({
            groupId,
            groupName,
            label,
            actionId,
            fx: x,
            fy: y,
            fw: width,
            fh: height,
            hasPreview,
            iconName,
            actionEnabled,
        });
    }

    function parsedGroupOrder() {
        const defaults = ["halves", "quarters", "thirds", "twoThirds", "custom", "window"];
        let stored = [];
        try {
            const parsed = JSON.parse(configuredGroupOrderJson);
            if (Array.isArray(parsed)) {
                stored = parsed;
            }
        } catch (error) {
            stored = [];
        }
        const order = stored.filter((groupId, index) =>
            defaults.indexOf(groupId) >= 0 && stored.indexOf(groupId) === index);
        defaults.forEach(groupId => {
            if (order.indexOf(groupId) < 0) {
                order.push(groupId);
            }
        });
        return order;
    }

    function reorderMenuGroups() {
        // ListModel roles are invalidated by clear(), so copy each role into a
        // plain object before rebuilding in the user's persisted group order.
        const items = [];
        for (let index = 0; index < layoutModel.count; index += 1) {
            const item = layoutModel.get(index);
            items.push({
                groupId: item.groupId,
                groupName: item.groupName,
                label: item.label,
                actionId: item.actionId,
                fx: item.fx,
                fy: item.fy,
                fw: item.fw,
                fh: item.fh,
                hasPreview: item.hasPreview,
                iconName: item.iconName,
                actionEnabled: item.actionEnabled,
            });
        }
        layoutModel.clear();
        const order = parsedGroupOrder();
        for (let groupIndex = 0; groupIndex < order.length; groupIndex += 1) {
            for (let itemIndex = 0; itemIndex < items.length; itemIndex += 1) {
                const item = items[itemIndex];
                if (item.groupId === order[groupIndex]) {
                    addMenuItem(
                        item.groupId,
                        item.groupName,
                        item.label,
                        item.actionId,
                        item.fx,
                        item.fy,
                        item.fw,
                        item.fh,
                        item.hasPreview,
                        item.iconName,
                        item.actionEnabled,
                    );
                }
            }
        }
    }

    function parsedCustomLayouts() {
        let parsed;
        try {
            parsed = JSON.parse(configuredLayoutsJson);
        } catch (error) {
            lastError = i18n("The custom layout configuration could not be read.");
            return [];
        }

        if (!Array.isArray(parsed)) {
            return [];
        }

        return parsed.slice(0, 20).filter(candidate => candidate
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
            && candidate.y + candidate.height <= 1.000001);
    }

    function rebuildMenu() {
        layoutModel.clear();

        addMenuItem("halves", i18n("Halves"), i18n("Left Half"), "WindowLayoutsLeftHalf", 0, 0, 0.5, 1, true, "");
        addMenuItem("halves", i18n("Halves"), i18n("Right Half"), "WindowLayoutsRightHalf", 0.5, 0, 0.5, 1, true, "");
        addMenuItem("halves", i18n("Halves"), i18n("Top Half"), "WindowLayoutsTopHalf", 0, 0, 1, 0.5, true, "");
        addMenuItem("halves", i18n("Halves"), i18n("Bottom Half"), "WindowLayoutsBottomHalf", 0, 0.5, 1, 0.5, true, "");

        addMenuItem("quarters", i18n("Quarters"), i18n("Top Left"), "WindowLayoutsTopLeft", 0, 0, 0.5, 0.5, true, "");
        addMenuItem("quarters", i18n("Quarters"), i18n("Top Right"), "WindowLayoutsTopRight", 0.5, 0, 0.5, 0.5, true, "");
        addMenuItem("quarters", i18n("Quarters"), i18n("Bottom Left"), "WindowLayoutsBottomLeft", 0, 0.5, 0.5, 0.5, true, "");
        addMenuItem("quarters", i18n("Quarters"), i18n("Bottom Right"), "WindowLayoutsBottomRight", 0.5, 0.5, 0.5, 0.5, true, "");

        addMenuItem("thirds", i18n("Thirds"), i18n("Left Third"), "WindowLayoutsLeftThird", 0, 0, 1 / 3, 1, true, "");
        addMenuItem("thirds", i18n("Thirds"), i18n("Center Third"), "WindowLayoutsCenterThird", 1 / 3, 0, 1 / 3, 1, true, "");
        addMenuItem("thirds", i18n("Thirds"), i18n("Right Third"), "WindowLayoutsRightThird", 2 / 3, 0, 1 / 3, 1, true, "");

        addMenuItem("twoThirds", i18n("Two Thirds"), i18n("Left Two Thirds"), "WindowLayoutsLeftTwoThirds", 0, 0, 2 / 3, 1, true, "");
        addMenuItem("twoThirds", i18n("Two Thirds"), i18n("Center Two Thirds"), "WindowLayoutsCenterTwoThirds", 1 / 6, 0, 2 / 3, 1, true, "");
        addMenuItem("twoThirds", i18n("Two Thirds"), i18n("Right Two Thirds"), "WindowLayoutsRightTwoThirds", 1 / 3, 0, 2 / 3, 1, true, "");

        const customLayouts = parsedCustomLayouts();
        for (let index = 0; index < customLayouts.length; index += 1) {
            const layout = customLayouts[index];
            addMenuItem(
                "custom",
                i18n("Custom"),
                layout.name.trim() || i18n("Custom Layout %1", index + 1),
                `WindowLayoutsCustom${index + 1}`,
                layout.x,
                layout.y,
                layout.width,
                layout.height,
                true,
                "",
            );
        }

        addMenuItem("window", i18n("Window"), i18n("Maximize"), "WindowLayoutsMaximize", 0, 0, 1, 1, true, "");
        addMenuItem("window", i18n("Window"), i18n("Center"), "WindowLayoutsCenter", 0.15, 0.15, 0.7, 0.7, true, "");
        addMenuItem("window", i18n("Window"), i18n("Restore"), "WindowLayoutsRestore", 0, 0, 0, 0, false, "window-restore");
        addMenuItem("window", i18n("Window"), i18n("Move to Previous Workspace"), "WindowLayoutsPreviousWorkspace", 0, 0, 0, 0, false, "go-previous", workspaceCount > 1);
        addMenuItem("window", i18n("Window"), i18n("Move to Next Workspace"), "WindowLayoutsNextWorkspace", 0, 0, 0, 0, false, "go-next", workspaceCount > 1);
        addMenuItem("window", i18n("Window"), i18n("Move to Previous Monitor"), "WindowLayoutsPreviousMonitor", 0, 0, 0, 0, false, "window-previous", monitorCount > 1);
        addMenuItem("window", i18n("Window"), i18n("Move to Next Monitor"), "WindowLayoutsNextMonitor", 0, 0, 0, 0, false, "window-next", monitorCount > 1);
        addMenuItem("window", i18n("Window"), i18n("Configure…"), "__configure__", 0, 0, 0, 0, false, "configure");
        reorderMenuGroups();
    }

    function refreshCapabilities() {
        capabilityRunner.connectSource(monitorQueryCommand);
        capabilityRunner.connectSource(workspaceQueryCommand);
    }

    function encodedArgument(value) {
        // encodeURIComponent leaves a few shell metacharacters unchanged.
        // Encoding those as well produces a single safe command argument.
        return encodeURIComponent(value).replace(/[!'()*]/g, character =>
            `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
    }

    function syncCustomLayouts() {
        const helperUrl = Qt.resolvedUrl("../tools/sync-layouts.sh").toString();
        const helperPath = decodeURIComponent(helperUrl.replace(/^file:\/\//, ""));
        const command = `${helperPath} ${encodedArgument(configuredLayoutsJson)}`;
        commandRunner.connectSource(command);
    }

    function syncFeatureSettings() {
        const helperUrl = Qt.resolvedUrl("../tools/sync-settings.sh").toString();
        const helperPath = decodeURIComponent(helperUrl.replace(/^file:\/\//, ""));
        const floatingValue = configuredFloatingButtonEnabled ? "true" : "false";
        const dragTargetsValue = configuredDragTargetsEnabled ? "true" : "false";
        const showAllValue = configuredShowAllDragTargets ? "true" : "false";
        commandRunner.connectSource(
            `${helperPath} ${floatingValue} ${dragTargetsValue} ${showAllValue} ${configuredFloatingButtonSize} ${encodedArgument(configuredGroupOrderJson)}`,
        );
    }

    function invokeAction(actionId) {
        if (actionId === "__configure__") {
            expanded = false;
            const configureAction = Plasmoid.internalAction("configure");
            if (configureAction) {
                configureAction.trigger();
            }
            return;
        }

        // actionId is selected from the model and contains no shell
        // metacharacters. KWin owns the registered global actions.
        const command = "qdbus-qt6 org.kde.kglobalaccel /component/kwin "
            + "org.kde.kglobalaccel.Component.invokeShortcut " + actionId;

        lastError = "";
        commandRunner.connectSource(command);
        expanded = false;
    }

    onConfiguredLayoutsJsonChanged: {
        if (componentReady) {
            rebuildMenu();
            syncCustomLayouts();
        }
    }

    onConfiguredFloatingButtonEnabledChanged: {
        if (componentReady) {
            featureSyncTimer.restart();
        }
    }

    onConfiguredDragTargetsEnabledChanged: {
        if (componentReady) {
            featureSyncTimer.restart();
        }
    }

    onConfiguredShowAllDragTargetsChanged: {
        if (componentReady) {
            featureSyncTimer.restart();
        }
    }

    onConfiguredFloatingButtonSizeChanged: {
        if (componentReady) {
            featureSyncTimer.restart();
        }
    }

    onConfiguredGroupOrderJsonChanged: {
        if (componentReady) {
            rebuildMenu();
            featureSyncTimer.restart();
        }
    }

    onMonitorCountChanged: {
        if (componentReady) {
            rebuildMenu();
        }
    }

    onWorkspaceCountChanged: {
        if (componentReady) {
            rebuildMenu();
        }
    }

    onExpandedChanged: {
        if (expanded) {
            refreshCapabilities();
        }
    }

    Component.onCompleted: {
        componentReady = true;
        rebuildMenu();
        syncCustomLayouts();
        refreshCapabilities();
    }

    ListModel {
        id: layoutModel
    }

    Plasma5Support.DataSource {
        id: commandRunner

        engine: "executable"

        onNewData: function(sourceName, data) {
            const exitCode = data["exit code"];
            if (exitCode !== undefined && exitCode !== 0) {
                root.lastError = data.stderr || i18n("Could not contact the Window Layouts KWin script.");
            }
            disconnectSource(sourceName);
        }
    }

    Plasma5Support.DataSource {
        id: capabilityRunner

        engine: "executable"

        onNewData: function(sourceName, data) {
            const exitCode = data["exit code"];
            if (exitCode === 0) {
                if (sourceName === root.monitorQueryCommand) {
                    try {
                        const screenData = JSON.parse(data.stdout || "{}");
                        const outputs = Array.isArray(screenData.outputs) ? screenData.outputs : [];
                        root.monitorCount = outputs.filter(output => output.connected && output.enabled).length;
                    } catch (error) {
                        root.monitorCount = 1;
                    }
                } else if (sourceName === root.workspaceQueryCommand) {
                    const count = Number.parseInt(data.stdout, 10);
                    root.workspaceCount = Number.isFinite(count) ? count : 1;
                }
            }
            disconnectSource(sourceName);
        }
    }

    Timer {
        id: featureSyncTimer

        interval: 50
        repeat: false
        onTriggered: root.syncFeatureSettings()
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.expanded
        onTriggered: root.refreshCapabilities()
    }

    compactRepresentation: MouseArea {
        id: compactRoot

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        hoverEnabled: true

        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: compactRoot.containsMouse
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 27

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 3
                text: i18n("Window Layouts")
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                color: Kirigami.Theme.disabledTextColor
                text: i18n("Apply a layout to the last active application window")
                wrapMode: Text.WordWrap
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.lastError.length > 0
                color: Kirigami.Theme.negativeTextColor
                text: root.lastError
                wrapMode: Text.WordWrap
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: layoutList

                    clip: true
                    model: layoutModel
                    spacing: Kirigami.Units.smallSpacing

                    section.property: "groupName"
                    section.delegate: PlasmaComponents3.Label {
                        required property string section

                        width: ListView.view.width
                        height: implicitHeight + Kirigami.Units.smallSpacing * 2
                        topPadding: Kirigami.Units.smallSpacing * 2
                        bottomPadding: Kirigami.Units.smallSpacing
                        text: section
                        font.bold: true
                    }

                    delegate: PlasmaComponents3.ItemDelegate {
                        id: layoutDelegate

                        required property string label
                        required property string actionId
                        required property real fx
                        required property real fy
                        required property real fw
                        required property real fh
                        required property bool hasPreview
                        required property string iconName
                        required property bool actionEnabled

                        width: ListView.view.width
                        height: Kirigami.Units.gridUnit * 2
                        enabled: actionEnabled
                        opacity: enabled ? 1 : 0.45
                        onClicked: root.invokeAction(actionId)

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing

                            Item {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: Kirigami.Theme.disabledTextColor
                                    border.width: 1
                                    radius: 2
                                }

                                Rectangle {
                                    visible: layoutDelegate.hasPreview
                                    x: Math.round(parent.width * layoutDelegate.fx)
                                    y: Math.round(parent.height * layoutDelegate.fy)
                                    width: Math.max(1, Math.round(parent.width * layoutDelegate.fw))
                                    height: Math.max(1, Math.round(parent.height * layoutDelegate.fh))
                                    color: Kirigami.Theme.highlightColor
                                    radius: 1
                                }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    visible: !layoutDelegate.hasPreview
                                    source: layoutDelegate.iconName
                                }
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: layoutDelegate.label
                            }
                        }
                    }
                }
            }
        }
    }
}
