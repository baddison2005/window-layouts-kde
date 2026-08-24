/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kwin
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore

PlasmaCore.Dialog {
    id: root

    property var targetWindow: null
    property rect trackedGeometry: Qt.rect(0, 0, 0, 0)
    property rect availableArea: Qt.rect(0, 0, 0, 0)
    property bool expanded: false
    property int monitorCount: 1
    property int workspaceCount: 1
    property string lastError: ""
    property bool targetEligible: false
    property bool targetRemapPending: false
    property int targetRevision: 0
    property string buttonSizeSetting: "default"

    readonly property color iconBlue: "#3daee9"
    readonly property real buttonSizeScale: buttonSizeSetting === "small"
        ? 2 / 3
        : (buttonSizeSetting === "big"
            ? 4 / 3
            : (buttonSizeSetting === "extraBig" ? 2 : 1))
    readonly property int compactExtent: Math.round(34 * buttonSizeScale)
    readonly property int compactIconMargin: Math.max(4, Math.round(7 * buttonSizeScale))
    readonly property int edgeGap: 6
    readonly property int windowTopOffset: 38
    readonly property int menuWidth: 340
    readonly property int preferredMenuHeight: 660
    title: "Window Layouts"
    // This surface is interactive, so it must use the normal floating-dialog
    // role. Desktop and OSD roles can be promoted to monitor-sized shell
    // layers on Wayland; with outputOnly disabled, that makes their invisible
    // input surface intercept clicks intended for application windows.
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Types.NoBackground
    flags: Qt.BypassWindowManagerHint
        | Qt.FramelessWindowHint
        | Qt.WindowDoesNotAcceptFocus
        | Qt.Tool
    hideOnWindowDeactivate: false
    // Pointer input is limited to this floating dialog's actual geometry.
    // Keep it enabled from surface creation so the compact button is usable.
    outputOnly: false
    // On Wayland the surface must be mapped only after its target geometry is
    // known. Mapping it at startup can pin it beneath the panel at (6, 6).
    visible: targetEligible
    width: expanded ? menuWidth : compactExtent
    height: expanded
        ? Math.min(preferredMenuHeight, Math.max(compactExtent, availableArea.height - edgeGap * 2))
        : compactExtent
    x: expanded ? expandedX() : compactX()
    y: expanded ? expandedY() : compactY()

    function isMaximizedWindow(window) {
        if (!window || window.deleted) {
            return false;
        }

        const mode = Number(window.maximizeMode);
        return Number.isFinite(mode) && mode !== 0;
    }

    function isSupportedWindow(window) {
        return window
            && !window.deleted
            && window.managed
            && window.normalWindow
            && !window.popupWindow
            && !window.skipTaskbar
            && !window.minimized
            && !window.fullScreen
            && !isMaximizedWindow(window);
    }

    function hasLayoutCapabilities(window) {
        return window && window.moveable && window.resizeable;
    }

    function isEligibleWindow(window) {
        // KWin can report the moveable/resizeable capabilities differently
        // while an interactive move or resize is in progress. Require them
        // when first acquiring a window, but do not drop an established
        // target just because those transient capability getters fluctuate.
        return isSupportedWindow(window)
            && (window === targetWindow || hasLayoutCapabilities(window));
    }

    function windowClaimsActivation(window) {
        return window && (window.active || window.move || window.resize);
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(value, maximum));
    }

    function loadFeatureSettings() {
        const configuredSize = String(KWin.readConfig("ButtonSize", "default"));
        buttonSizeSetting = ["small", "default", "big", "extraBig"].indexOf(configuredSize) >= 0
            ? configuredSize
            : "default";
    }

    function compactUsesLeftSide() {
        const maximum = availableArea.x + availableArea.width - compactExtent - edgeGap;
        const outsideRight = trackedGeometry.x + trackedGeometry.width + edgeGap;
        return outsideRight > maximum;
    }

    function compactX() {
        const minimum = availableArea.x + edgeGap;
        const maximum = availableArea.x + availableArea.width - compactExtent - edgeGap;
        const outsideRight = trackedGeometry.x + trackedGeometry.width + edgeGap;
        if (outsideRight <= maximum) {
            return outsideRight;
        }

        const outsideLeft = trackedGeometry.x - compactExtent - edgeGap;
        if (outsideLeft >= minimum) {
            return outsideLeft;
        }

        const insideLeft = trackedGeometry.x + edgeGap;
        return Math.round(clamp(insideLeft, minimum, maximum));
    }

    function compactY() {
        const minimum = availableArea.y + edgeGap;
        const maximum = availableArea.y + availableArea.height - compactExtent - edgeGap;
        return Math.round(clamp(trackedGeometry.y + windowTopOffset, minimum, maximum));
    }

    function expandedX() {
        const minimum = availableArea.x + edgeGap;
        const maximum = availableArea.x + availableArea.width - width - edgeGap;
        const alignedToButton = compactUsesLeftSide()
            ? trackedGeometry.x
            : trackedGeometry.x + trackedGeometry.width - width;
        return Math.round(clamp(alignedToButton, minimum, maximum));
    }

    function expandedY() {
        const minimum = availableArea.y + edgeGap;
        const maximum = availableArea.y + availableArea.height - height - edgeGap;
        return Math.round(clamp(trackedGeometry.y + windowTopOffset, minimum, maximum));
    }

    function refreshCapabilities() {
        const outputs = Workspace.screenOrder;
        monitorCount = outputs && outputs.length ? outputs.length : 1;
        const desktops = Workspace.desktops;
        workspaceCount = desktops && desktops.length ? desktops.length : 1;
    }

    function refreshTargetGeometry() {
        if (!targetWindow || targetWindow.deleted) {
            targetEligible = false;
            return;
        }

        if (!isEligibleWindow(targetWindow)) {
            targetEligible = false;
            expanded = false;
            return;
        }

        const geometry = targetWindow.frameGeometry;
        trackedGeometry = Qt.rect(geometry.x, geometry.y, geometry.width, geometry.height);
        const area = Workspace.clientArea(KWin.MaximizeArea, targetWindow);
        availableArea = Qt.rect(area.x, area.y, area.width, area.height);
        refreshCapabilities();
    }

    function trackInteractiveGeometry(geometry) {
        if (!geometry || !targetWindow || targetWindow.deleted) {
            return;
        }

        trackedGeometry = Qt.rect(geometry.x, geometry.y, geometry.width, geometry.height);
        const area = Workspace.clientArea(KWin.MaximizeArea, targetWindow);
        availableArea = Qt.rect(area.x, area.y, area.width, area.height);
    }

    function hideTarget(clearTarget = false) {
        targetRevision += 1;
        targetRemapPending = false;
        expanded = false;
        targetEligible = false;
        if (clearTarget) {
            targetWindow = null;
        }
    }

    function finishTargetRemap(window, revision) {
        if (revision !== targetRevision || targetWindow !== window) {
            return;
        }

        targetRemapPending = false;
        if (!isEligibleWindow(window)
                || (Workspace.activeWindow !== window && !windowClaimsActivation(window))) {
            targetEligible = false;
            return;
        }

        refreshTargetGeometry();
        // Geometry is now final. Mapping only at this point prevents the
        // Wayland surface from remaining at the previous window's position.
        targetEligible = isEligibleWindow(window);
    }

    function remapTarget(window) {
        if (!isEligibleWindow(window) || targetRemapPending) {
            return;
        }

        expanded = false;
        targetEligible = false;
        targetRemapPending = true;
        targetRevision += 1;
        const revision = targetRevision;
        targetWindow = window;
        refreshTargetGeometry();
        Qt.callLater(() => finishTargetRemap(window, revision));
    }

    function updateTarget(window) {
        if (!isEligibleWindow(window)) {
            hideTarget(window && window.deleted);
            return;
        }

        if (targetWindow !== window) {
            // PlasmaCore.Dialog cannot always move an already-mapped Wayland
            // surface cleanly from one application window to another. Force a
            // one-event-loop unmap/remap whenever the active window changes.
            remapTarget(window);
            return;
        }

        if (targetRemapPending) {
            return;
        }

        refreshTargetGeometry();
        targetEligible = isEligibleWindow(targetWindow);
    }

    function syncActiveWindow() {
        const activeWindow = Workspace.activeWindow;
        if (isEligibleWindow(activeWindow)) {
            updateTarget(activeWindow);
            return;
        }

        // KWin can briefly clear Workspace.activeWindow during an interactive
        // move/resize. Keep following the established target while the window
        // itself still reports active, move, or resize state.
        if (isEligibleWindow(targetWindow)
                && windowClaimsActivation(targetWindow)
                && (!activeWindow || activeWindow === targetWindow)) {
            if (!targetRemapPending) {
                refreshTargetGeometry();
                targetEligible = true;
            }
            return;
        }

        // Hide while the desktop, a special surface, a minimized window, a
        // maximized window, or a fullscreen window owns focus. Retaining a
        // valid target pointer makes restoration immediate on reactivation.
        hideTarget(targetWindow && targetWindow.deleted);
    }

    function addMenuItem(groupId, groupName, label, actionId, x, y, width, height, hasPreview, iconName, actionEnabled = true, previewLayoutsJson = "[]") {
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
            previewLayoutsJson,
        });
    }

    function configuredGroupOrder() {
        // Read stable IDs from KWin configuration, never visible labels. This
        // keeps an existing order intact when Plasma's display language changes.
        const defaults = ["halves", "quarters", "thirds", "twoThirds", "custom", "fillDisplay", "window"];
        let stored = [];
        try {
            const parsed = JSON.parse(String(KWin.readConfig("GroupOrder", "[]")));
            if (Array.isArray(parsed)) {
                stored = parsed;
            }
        } catch (error) {
            stored = [];
        }
        const order = stored.filter((groupId, index) =>
            defaults.indexOf(groupId) >= 0 && stored.indexOf(groupId) === index);
        if (order.indexOf("fillDisplay") < 0) {
            const windowIndex = order.indexOf("window");
            order.splice(windowIndex >= 0 ? windowIndex : order.length, 0, "fillDisplay");
        }
        defaults.forEach(groupId => {
            if (order.indexOf(groupId) < 0) {
                order.push(groupId);
            }
        });
        return order;
    }

    function reorderMenuGroups() {
        // Copy roles before clear(); objects returned by ListModel.get() are
        // backed by that model and cannot safely survive a rebuild.
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
                previewLayoutsJson: item.previewLayoutsJson,
            });
        }
        layoutModel.clear();
        const order = configuredGroupOrder();
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
                        item.previewLayoutsJson,
                    );
                }
            }
        }
    }

    function validatedCustomLayouts() {
        let parsed;
        try {
            parsed = JSON.parse(String(KWin.readConfig("CustomLayouts", "[]")));
        } catch (error) {
            lastError = "The custom layout configuration could not be read.";
            return [];
        }

        if (!Array.isArray(parsed)) {
            return [];
        }

        const layouts = [];
        const usedSlots = [];
        const candidates = parsed.slice(0, 20);
        for (let index = 0; index < candidates.length; index += 1) {
            const candidate = candidates[index];
            if (!candidate
                    || typeof candidate.name !== "string"
                    || !Number.isFinite(candidate.x)
                    || !Number.isFinite(candidate.y)
                    || !Number.isFinite(candidate.width)
                    || !Number.isFinite(candidate.height)
                    || candidate.x < 0
                    || candidate.y < 0
                    || candidate.width <= 0
                    || candidate.height <= 0
                    || candidate.x + candidate.width > 1.000001
                    || candidate.y + candidate.height > 1.000001) {
                continue;
            }
            let shortcutSlot = Number.isInteger(candidate.shortcutSlot)
                && candidate.shortcutSlot >= 1
                && candidate.shortcutSlot <= 20
                && usedSlots.indexOf(candidate.shortcutSlot) < 0
                    ? candidate.shortcutSlot
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
            layouts.push({
                name: candidate.name,
                x: candidate.x,
                y: candidate.y,
                width: candidate.width,
                height: candidate.height,
                shortcutSlot,
                groupId: typeof candidate.groupId === "string" ? candidate.groupId : "",
            });
        }
        return layouts;
    }

    function configuredCustomGroups() {
        const groups = {};
        configuredCustomGroupList().forEach(group => {
            groups[group.id] = group.name;
        });
        return groups;
    }

    function configuredCustomGroupList() {
        let parsed = [];
        try {
            const candidate = JSON.parse(String(KWin.readConfig("CustomGroups", "[]")));
            if (Array.isArray(candidate)) {
                parsed = candidate;
            }
        } catch (error) {
            parsed = [];
        }
        const groups = [];
        const usedIds = [];
        const usedSlots = [];
        parsed.slice(0, 20).forEach(group => {
            if (group
                    && typeof group.id === "string"
                    && group.id.length > 0
                    && typeof group.name === "string"
                    && group.name.trim().length > 0
                    && usedIds.indexOf(group.id) < 0) {
                let slot = Number.isInteger(group.fillShortcutSlot)
                    && group.fillShortcutSlot >= 1
                    && group.fillShortcutSlot <= 20
                    && usedSlots.indexOf(group.fillShortcutSlot) < 0
                        ? group.fillShortcutSlot
                        : -1;
                if (slot < 0) {
                    for (let candidate = 1; candidate <= 20; candidate += 1) {
                        if (usedSlots.indexOf(candidate) < 0) {
                            slot = candidate;
                            break;
                        }
                    }
                }
                usedIds.push(group.id);
                usedSlots.push(slot);
                groups.push({ id: group.id, name: group.name.trim(), fillShortcutSlot: slot });
            }
        });
        return groups;
    }

    function customLayoutsInGroupOrder(layouts, groups) {
        const ordered = layouts.filter(layout => !groups[layout.groupId]);
        Object.keys(groups).forEach(groupId => {
            layouts.forEach(layout => {
                if (layout.groupId === groupId) {
                    ordered.push(layout);
                }
            });
        });
        return ordered;
    }

    function fillPreviewJson(previewLayouts) {
        return JSON.stringify(previewLayouts.map(layout => ({
            x: layout.x,
            y: layout.y,
            width: layout.width,
            height: layout.height,
        })));
    }

    function rebuildMenu() {
        layoutModel.clear();
        lastError = "";

        addMenuItem("halves", "Halves", "Left Half", "WindowLayoutsLeftHalf", 0, 0, 0.5, 1, true, "");
        addMenuItem("halves", "Halves", "Right Half", "WindowLayoutsRightHalf", 0.5, 0, 0.5, 1, true, "");
        addMenuItem("halves", "Halves", "Top Half", "WindowLayoutsTopHalf", 0, 0, 1, 0.5, true, "");
        addMenuItem("halves", "Halves", "Bottom Half", "WindowLayoutsBottomHalf", 0, 0.5, 1, 0.5, true, "");

        addMenuItem("quarters", "Quarters", "Top Left", "WindowLayoutsTopLeft", 0, 0, 0.5, 0.5, true, "");
        addMenuItem("quarters", "Quarters", "Top Right", "WindowLayoutsTopRight", 0.5, 0, 0.5, 0.5, true, "");
        addMenuItem("quarters", "Quarters", "Bottom Left", "WindowLayoutsBottomLeft", 0, 0.5, 0.5, 0.5, true, "");
        addMenuItem("quarters", "Quarters", "Bottom Right", "WindowLayoutsBottomRight", 0.5, 0.5, 0.5, 0.5, true, "");

        addMenuItem("thirds", "Thirds", "Left Third", "WindowLayoutsLeftThird", 0, 0, 1 / 3, 1, true, "");
        addMenuItem("thirds", "Thirds", "Center Third", "WindowLayoutsCenterThird", 1 / 3, 0, 1 / 3, 1, true, "");
        addMenuItem("thirds", "Thirds", "Right Third", "WindowLayoutsRightThird", 2 / 3, 0, 1 / 3, 1, true, "");

        addMenuItem("twoThirds", "Two Thirds", "Left Two Thirds", "WindowLayoutsLeftTwoThirds", 0, 0, 2 / 3, 1, true, "");
        addMenuItem("twoThirds", "Two Thirds", "Center Two Thirds", "WindowLayoutsCenterTwoThirds", 1 / 6, 0, 2 / 3, 1, true, "");
        addMenuItem("twoThirds", "Two Thirds", "Right Two Thirds", "WindowLayoutsRightTwoThirds", 1 / 3, 0, 2 / 3, 1, true, "");

        let customLayouts = validatedCustomLayouts();
        const customGroups = configuredCustomGroups();
        customLayouts = customLayoutsInGroupOrder(customLayouts, customGroups);
        for (let index = 0; index < customLayouts.length; index += 1) {
            const layout = customLayouts[index];
            addMenuItem(
                "custom",
                customGroups[layout.groupId] || "Custom",
                layout.name.trim() || `Custom Layout ${index + 1}`,
                `WindowLayoutsCustom${layout.shortcutSlot}`,
                layout.x,
                layout.y,
                layout.width,
                layout.height,
                true,
                "",
            );
        }

        addMenuItem("fillDisplay", "Fill Display", "Horizontal Halves", "WindowLayoutsFillHorizontalHalves", 0, 0, 0, 0, false, "", true, fillPreviewJson([
            { x: 0, y: 0, width: 0.5, height: 1 }, { x: 0.5, y: 0, width: 0.5, height: 1 },
        ]));
        addMenuItem("fillDisplay", "Fill Display", "Vertical Halves", "WindowLayoutsFillVerticalHalves", 0, 0, 0, 0, false, "", true, fillPreviewJson([
            { x: 0, y: 0, width: 1, height: 0.5 }, { x: 0, y: 0.5, width: 1, height: 0.5 },
        ]));
        addMenuItem("fillDisplay", "Fill Display", "Quarters", "WindowLayoutsFillQuarters", 0, 0, 0, 0, false, "", true, fillPreviewJson([
            { x: 0, y: 0, width: 0.5, height: 0.5 }, { x: 0.5, y: 0, width: 0.5, height: 0.5 },
            { x: 0, y: 0.5, width: 0.5, height: 0.5 }, { x: 0.5, y: 0.5, width: 0.5, height: 0.5 },
        ]));
        addMenuItem("fillDisplay", "Fill Display", "Thirds", "WindowLayoutsFillThirds", 0, 0, 0, 0, false, "", true, fillPreviewJson([
            { x: 0, y: 0, width: 1 / 3, height: 1 }, { x: 1 / 3, y: 0, width: 1 / 3, height: 1 },
            { x: 2 / 3, y: 0, width: 1 / 3, height: 1 },
        ]));
        const customGroupList = configuredCustomGroupList();
        for (let groupIndex = 0; groupIndex < customGroupList.length; groupIndex += 1) {
            const group = customGroupList[groupIndex];
            const hasLayouts = customLayouts.some(layout => layout.groupId === group.id);
            if (hasLayouts) {
                addMenuItem(
                    "fillDisplay",
                    "Fill Display",
                    group.name,
                    `WindowLayoutsFillCustomGroup${group.fillShortcutSlot}`,
                    0, 0, 0, 0, false, "", true,
                    fillPreviewJson(customLayouts.filter(layout => layout.groupId === group.id)),
                );
            }
        }

        addMenuItem("window", "Window", "Maximize", "WindowLayoutsMaximize", 0, 0, 1, 1, true, "");
        addMenuItem("window", "Window", "Center", "WindowLayoutsCenter", 0.15, 0.15, 0.7, 0.7, true, "");
        addMenuItem("window", "Window", "Restore", "WindowLayoutsRestore", 0, 0, 0, 0, false, "window-restore");
        addMenuItem("window", "Window", "Move to Previous Workspace", "WindowLayoutsPreviousWorkspace", 0, 0, 0, 0, false, "go-previous", workspaceCount > 1);
        addMenuItem("window", "Window", "Move to Next Workspace", "WindowLayoutsNextWorkspace", 0, 0, 0, 0, false, "go-next", workspaceCount > 1);
        addMenuItem("window", "Window", "Move to Previous Monitor", "WindowLayoutsPreviousMonitor", 0, 0, 0, 0, false, "window-previous", monitorCount > 1);
        addMenuItem("window", "Window", "Move to Next Monitor", "WindowLayoutsNextMonitor", 0, 0, 0, 0, false, "window-next", monitorCount > 1);
        addMenuItem("window", "Window", "Configure…", "WindowLayoutsConfigure", 0, 0, 0, 0, false, "configure");
        reorderMenuGroups();
    }

    function invokeAction(actionId) {
        actionCall.arguments = [actionId];
        actionCall.call();
        expanded = false;
    }

    function setFloatingButtonEnabled(enabled) {
        featureSettingsCall.arguments = [enabled];
        featureSettingsCall.call();
        if (!enabled) {
            // Hide immediately. The shared settings service will persist the
            // change and ask KWin to unload this script a moment later.
            expanded = false;
            targetEligible = false;
        }
    }

    onExpandedChanged: {
        if (expanded) {
            refreshTargetGeometry();
            rebuildMenu();
        }
    }

    Component.onCompleted: {
        loadFeatureSettings();
        rebuildMenu();
        syncActiveWindow();
    }

    mainItem: Item {
        id: dialogContent

        width: root.width
        height: root.height

        ListModel {
            id: layoutModel
        }

    Connections {
        target: Workspace
        ignoreUnknownSignals: true

        function onDesktopsChanged() {
            root.refreshCapabilities();
            if (root.expanded) {
                root.rebuildMenu();
            }
        }

        function onScreensChanged() {
            root.refreshTargetGeometry();
            if (root.expanded) {
                root.rebuildMenu();
            }
        }
    }

    Connections {
        target: root.targetWindow
        ignoreUnknownSignals: true

        function onFrameGeometryChanged() {
            root.refreshTargetGeometry();
        }

        function onInteractiveMoveResizeStarted() {
            root.remapTarget(root.targetWindow);
        }

        function onInteractiveMoveResizeStepped(geometry) {
            root.trackInteractiveGeometry(geometry);
        }

        function onInteractiveMoveResizeFinished() {
            root.syncActiveWindow();
        }

        function onMoveResizedChanged() {
            if (root.targetWindow && (root.targetWindow.move || root.targetWindow.resize)) {
                root.remapTarget(root.targetWindow);
            } else {
                root.syncActiveWindow();
            }
        }

        function onActiveChanged() {
            Qt.callLater(root.syncActiveWindow);
        }

        function onFullScreenChanged() {
            root.syncActiveWindow();
        }

        function onMaximizedChanged() {
            root.syncActiveWindow();
        }

        function onMinimizedChanged() {
            root.syncActiveWindow();
        }

        function onOutputChanged() {
            root.refreshTargetGeometry();
        }

        function onClosed() {
            root.hideTarget(true);
            Qt.callLater(root.syncActiveWindow);
        }
    }

    Connections {
        target: Options
        ignoreUnknownSignals: true

        function onConfigChanged() {
            root.loadFeatureSettings();
            root.rebuildMenu();
            root.refreshTargetGeometry();
        }
    }

    ShortcutHandler {
        name: "WindowLayoutsToggleFloatingMenu"
        text: "Window Layouts: Toggle Floating Menu"
        sequence: ""
        onActivated: {
            root.syncActiveWindow();
            if (root.targetEligible) {
                root.expanded = !root.expanded;
            }
        }
    }

    DBusCall {
        id: actionCall

        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        method: "invokeShortcut"
    }

    DBusCall {
        id: featureSettingsCall

        service: "org.example.WindowLayouts.Configurator"
        path: "/org/example/WindowLayouts/Configurator"
        method: "SetFloatingButtonEnabled"
    }

    Rectangle {
        id: compactButton

        anchors.fill: parent
        visible: root.targetEligible && !root.expanded
        radius: width / 2
        color: compactMouse.containsMouse
            ? Kirigami.Theme.alternateBackgroundColor
            : Kirigami.Theme.backgroundColor
        border.width: 2
        border.color: root.iconBlue
        opacity: compactMouse.pressed ? 1 : (compactMouse.containsMouse ? 0.8 : 0.5)

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: root.compactIconMargin
            source: Qt.resolvedUrl("../../images/window-layouts.svg")
        }

        MouseArea {
            id: compactMouse

            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = true
        }

        QQC2.ToolTip {
            visible: compactMouse.containsMouse
            text: "Window Layouts"
            delay: Kirigami.Units.toolTipDelay
        }
    }

        Rectangle {
            anchors.fill: parent
            visible: root.expanded
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Kirigami.Theme.highlightColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: width
                    source: Qt.resolvedUrl("../../images/window-layouts.svg")
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: "Window Layouts"
                    font.bold: true
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    text: "Close"
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: root.expanded = false

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                }
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
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        text: section
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
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
                        required property string previewLayoutsJson

                        readonly property var previewLayouts: {
                            try {
                                const parsed = JSON.parse(previewLayoutsJson);
                                return Array.isArray(parsed) ? parsed : [];
                            } catch (error) {
                                return [];
                            }
                        }

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
                                    color: "#a855f7"
                                    radius: 1
                                }

                                Repeater {
                                    model: layoutDelegate.previewLayouts

                                    delegate: Rectangle {
                                        required property var modelData

                                        x: Math.round(parent.width * modelData.x)
                                        y: Math.round(parent.height * modelData.y)
                                        width: Math.max(1, Math.round(parent.width * modelData.width))
                                        height: Math.max(1, Math.round(parent.height * modelData.height))
                                        color: "#a855f7"
                                        border.color: Kirigami.Theme.backgroundColor
                                        border.width: 1
                                        radius: 1
                                    }
                                }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    visible: !layoutDelegate.hasPreview
                                        && layoutDelegate.previewLayouts.length === 0
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

            QQC2.Switch {
                Layout.fillWidth: true
                text: "Show floating button"
                checked: true
                onToggled: {
                    if (!checked) {
                        root.setFloatingButtonEnabled(false);
                    }
                }
            }
            }
        }
    }
}
