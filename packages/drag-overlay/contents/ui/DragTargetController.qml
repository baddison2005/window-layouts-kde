/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin
import org.kde.plasma.core as PlasmaCore

QtObject {
    id: controller

    readonly property color accentBlue: "#3daee9"
    readonly property int maximumCustomLayouts: 20
    readonly property int targetWidth: 116
    readonly property int targetHeight: 80
    readonly property int targetGap: 12
    readonly property int screenMargin: 12
    readonly property int revealedGroupPadding: 18
    readonly property int maximumLayoutPadding: 200

    property var signalWindow: null
    property var dragWindow: null
    property var currentOutput: null
    property rect availableArea: Qt.rect(0, 0, 0, 0)
    property var targets: []
    property string revealedGroupKey: ""
    property int hoveredIndex: -1
    property int idleFullScanCounter: 0
    property rect hoveredPreview: Qt.rect(0, 0, 0, 0)
    property bool dragActive: false
    property bool overlayMapped: false
    property string targetPlacement: "zones"
    property bool showAllTargets: false
    property bool showAllTopTargets: false
    property bool topTargetsRevealed: false
    property int layoutPadding: 0
    property rect topStripRect: Qt.rect(0, 0, 0, 0)
    property int mappingRevision: 0

    function loadFeatureSettings() {
        const configuredPlacement = String(KWin.readConfig("TargetPlacement", "zones"));
        targetPlacement = configuredPlacement === "top" ? "top" : "zones";

        const configured = String(KWin.readConfig("ShowAllTargets", "false")).toLowerCase();
        showAllTargets = configured === "true"
            || configured === "1"
            || configured === "yes"
            || configured === "on";

        const configuredTop = String(KWin.readConfig("ShowAllTopTargets", "false")).toLowerCase();
        showAllTopTargets = configuredTop === "true"
            || configuredTop === "1"
            || configuredTop === "yes"
            || configuredTop === "on";

        const configuredPadding = Number(KWin.readConfig("LayoutPadding", 0));
        layoutPadding = Number.isFinite(configuredPadding)
            ? clamp(Math.round(configuredPadding), 0, maximumLayoutPadding)
            : 0;
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(value, maximum));
    }

    function constrainedInsets(size, startInset, endInset) {
        const maximumTotal = Math.max(0, size - 1);
        const requestedTotal = startInset + endInset;
        if (requestedTotal <= maximumTotal) {
            return { start: startInset, end: endInset };
        }
        if (requestedTotal <= 0) {
            return { start: 0, end: 0 };
        }
        const start = Math.floor(maximumTotal * startInset / requestedTotal);
        return { start, end: maximumTotal - start };
    }

    function isMaximizedWindow(window) {
        if (!window || window.deleted) {
            return false;
        }

        const mode = Number(window.maximizeMode);
        return Number.isFinite(mode) && mode !== 0;
    }

    function isEligibleWindow(window) {
        return window
            && !window.deleted
            && window.managed
            && window.normalWindow
            && !window.popupWindow
            && !window.minimized
            && !window.fullScreen
            && !isMaximizedWindow(window)
            && window.moveable
            && window.resizeable;
    }

    function isInteractiveMove(window) {
        return isEligibleWindow(window) && window.move && !window.resize;
    }

    function fixedLayouts() {
        return [
            { groupId: "halves", actionId: "WindowLayoutsLeftHalf", name: "Left Half", x: 0, y: 0, width: 1 / 2, height: 1, kind: "layout" },
            { groupId: "halves", actionId: "WindowLayoutsRightHalf", name: "Right Half", x: 1 / 2, y: 0, width: 1 / 2, height: 1, kind: "layout" },
            { groupId: "halves", actionId: "WindowLayoutsTopHalf", name: "Top Half", x: 0, y: 0, width: 1, height: 1 / 2, kind: "layout" },
            { groupId: "halves", actionId: "WindowLayoutsBottomHalf", name: "Bottom Half", x: 0, y: 1 / 2, width: 1, height: 1 / 2, kind: "layout" },

            { groupId: "quarters", actionId: "WindowLayoutsTopLeft", name: "Top Left", x: 0, y: 0, width: 1 / 2, height: 1 / 2, kind: "layout" },
            { groupId: "quarters", actionId: "WindowLayoutsTopRight", name: "Top Right", x: 1 / 2, y: 0, width: 1 / 2, height: 1 / 2, kind: "layout" },
            { groupId: "quarters", actionId: "WindowLayoutsBottomLeft", name: "Bottom Left", x: 0, y: 1 / 2, width: 1 / 2, height: 1 / 2, kind: "layout" },
            { groupId: "quarters", actionId: "WindowLayoutsBottomRight", name: "Bottom Right", x: 1 / 2, y: 1 / 2, width: 1 / 2, height: 1 / 2, kind: "layout" },

            { groupId: "thirds", actionId: "WindowLayoutsLeftThird", name: "Left Third", x: 0, y: 0, width: 1 / 3, height: 1, kind: "layout" },
            { groupId: "thirds", actionId: "WindowLayoutsCenterThird", name: "Center Third", x: 1 / 3, y: 0, width: 1 / 3, height: 1, kind: "layout" },
            { groupId: "thirds", actionId: "WindowLayoutsRightThird", name: "Right Third", x: 2 / 3, y: 0, width: 1 / 3, height: 1, kind: "layout" },

            { groupId: "twoThirds", actionId: "WindowLayoutsLeftTwoThirds", name: "Left Two Thirds", x: 0, y: 0, width: 2 / 3, height: 1, kind: "layout" },
            { groupId: "twoThirds", actionId: "WindowLayoutsCenterTwoThirds", name: "Center Two Thirds", x: 1 / 6, y: 0, width: 2 / 3, height: 1, kind: "layout" },
            { groupId: "twoThirds", actionId: "WindowLayoutsRightTwoThirds", name: "Right Two Thirds", x: 1 / 3, y: 0, width: 2 / 3, height: 1, kind: "layout" },
        ];
    }

    function validatedCustomLayouts() {
        let parsed;
        try {
            parsed = JSON.parse(String(KWin.readConfig("CustomLayouts", "[]")));
        } catch (error) {
            console.warn(`window-layouts-drag-overlay: Could not parse custom layouts: ${error}`);
            return [];
        }

        if (!Array.isArray(parsed)) {
            return [];
        }

        const validated = [];
        const usedSlots = [];
        const candidates = parsed.slice(0, maximumCustomLayouts);
        for (let index = 0; index < candidates.length; index += 1) {
            const candidate = candidates[index];
            if (!candidate || typeof candidate !== "object") {
                continue;
            }

            const x = candidate.x;
            const y = candidate.y;
            const width = candidate.width;
            const height = candidate.height;
            if (!Number.isFinite(x)
                    || !Number.isFinite(y)
                    || !Number.isFinite(width)
                    || !Number.isFinite(height)
                    || x < 0
                    || y < 0
                    || width <= 0
                    || height <= 0
                    || x + width > 1.000001
                    || y + height > 1.000001) {
                continue;
            }

            const configuredName = typeof candidate.name === "string"
                ? candidate.name.trim()
                : "";
            let shortcutSlot = Number.isInteger(candidate.shortcutSlot)
                && candidate.shortcutSlot >= 1
                && candidate.shortcutSlot <= maximumCustomLayouts
                && usedSlots.indexOf(candidate.shortcutSlot) < 0
                    ? candidate.shortcutSlot
                    : -1;
            if (shortcutSlot < 0) {
                for (let slot = 1; slot <= maximumCustomLayouts; slot += 1) {
                    if (usedSlots.indexOf(slot) < 0) {
                        shortcutSlot = slot;
                        break;
                    }
                }
            }
            usedSlots.push(shortcutSlot);
            validated.push({
                groupId: "custom",
                actionId: `WindowLayoutsCustom${shortcutSlot}`,
                name: configuredName || `Custom Layout ${index + 1}`,
                x,
                y,
                width,
                height,
                kind: "layout",
                customGroupId: typeof candidate.groupId === "string" ? candidate.groupId : "",
            });
        }

        let groups = [];
        try {
            const parsedGroups = JSON.parse(String(KWin.readConfig("CustomGroups", "[]")));
            if (Array.isArray(parsedGroups)) {
                groups = parsedGroups
                    .filter(group => group && typeof group.id === "string")
                    .map(group => group.id);
            }
        } catch (error) {
            groups = [];
        }
        const ordered = validated.filter(layout => groups.indexOf(layout.customGroupId) < 0);
        groups.forEach(groupId => {
            validated.forEach(layout => {
                if (layout.customGroupId === groupId) {
                    ordered.push(layout);
                }
            });
        });
        return ordered;
    }

    function allLayouts() {
        // Group order has no effect on geometry, but it deliberately controls
        // the stacking order of cards whose layout centers are identical.
        const defaults = ["halves", "quarters", "thirds", "twoThirds", "custom", "window"];
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
        defaults.forEach(groupId => {
            if (order.indexOf(groupId) < 0) {
                order.push(groupId);
            }
        });

        const grouped = {};
        defaults.forEach(groupId => grouped[groupId] = []);
        fixedLayouts().concat(validatedCustomLayouts()).forEach(layout => {
            grouped[layout.groupId].push(layout);
        });
        grouped.window.push({
            groupId: "window",
            actionId: "WindowLayoutsMaximize",
            name: "Maximize",
            x: 0,
            y: 0,
            width: 1,
            height: 1,
            kind: "maximize",
        });
        grouped.window.push({
            groupId: "window",
            actionId: "WindowLayoutsCenter",
            name: "Center",
            x: 0.15,
            y: 0.15,
            width: 0.7,
            height: 0.7,
            kind: "center",
        });
        let layouts = [];
        order.forEach(groupId => layouts = layouts.concat(grouped[groupId]));
        return layouts;
    }

    function rebuildTargets() {
        if (availableArea.width <= 0 || availableArea.height <= 0) {
            targets = [];
            revealedGroupKey = "";
            topStripRect = Qt.rect(0, 0, 0, 0);
            return;
        }

        const layouts = allLayouts();
        if (targetPlacement === "top") {
            const availableColumns = Math.max(1, Math.floor(
                (availableArea.width - screenMargin * 2 + targetGap)
                    / (targetWidth + targetGap),
            ));
            // Ten columns keeps the strip centered and reachable on wide
            // displays while allowing additional rows for custom layouts.
            const columnCount = Math.max(1, Math.min(
                layouts.length,
                Math.min(10, availableColumns),
            ));
            const positioned = [];
            let minimumX = Number.POSITIVE_INFINITY;
            let minimumY = Number.POSITIVE_INFINITY;
            let maximumX = Number.NEGATIVE_INFINITY;
            let maximumY = Number.NEGATIVE_INFINITY;

            for (let index = 0; index < layouts.length; index += 1) {
                const row = Math.floor(index / columnCount);
                const firstInRow = row * columnCount;
                const columnsInRow = Math.min(columnCount, layouts.length - firstInRow);
                const rowWidth = columnsInRow * targetWidth
                    + Math.max(0, columnsInRow - 1) * targetGap;
                const rowLeft = Math.round((availableArea.width - rowWidth) / 2);
                const column = index - firstInRow;
                const targetX = rowLeft + column * (targetWidth + targetGap);
                const targetY = screenMargin + row * (targetHeight + targetGap);
                const layout = layouts[index];
                positioned.push({
                    actionId: layout.actionId,
                    name: layout.name,
                    x: layout.x,
                    y: layout.y,
                    width: layout.width,
                    height: layout.height,
                    kind: layout.kind,
                    groupKey: "top",
                    centerX: layout.x + layout.width / 2,
                    centerY: layout.y + layout.height / 2,
                    targetX,
                    targetY,
                });
                minimumX = Math.min(minimumX, targetX);
                minimumY = Math.min(minimumY, targetY);
                maximumX = Math.max(maximumX, targetX + targetWidth);
                maximumY = Math.max(maximumY, targetY + targetHeight);
            }

            targets = positioned;
            topStripRect = positioned.length > 0
                ? Qt.rect(
                    minimumX - 10,
                    minimumY - 10,
                    maximumX - minimumX + 20,
                    maximumY - minimumY + 20,
                )
                : Qt.rect(0, 0, 0, 0);
            revealedGroupKey = "";
            topTargetsRevealed = false;
            hoveredIndex = -1;
            hoveredPreview = Qt.rect(0, 0, 0, 0);
            return;
        }

        topStripRect = Qt.rect(0, 0, 0, 0);
        const groups = {};
        for (let index = 0; index < layouts.length; index += 1) {
            const layout = layouts[index];
            const centerX = layout.x + layout.width / 2;
            const centerY = layout.y + layout.height / 2;
            // Custom layouts use a 24 x 12 grid. Quantizing more finely than
            // that groups mathematically identical centers while preserving
            // genuinely nearby, but distinct, target positions.
            const key = `${Math.round(centerX * 10000)}:${Math.round(centerY * 10000)}`;
            if (!groups[key]) {
                groups[key] = [];
            }
            groups[key].push({ layout, centerX, centerY });
        }

        const positioned = [];
        const groupKeys = Object.keys(groups);
        for (let groupIndex = 0; groupIndex < groupKeys.length; groupIndex += 1) {
            const group = groups[groupKeys[groupIndex]];
            const maximumRows = Math.max(1, Math.floor(
                (availableArea.height - screenMargin * 2 + targetGap)
                    / (targetHeight + targetGap),
            ));
            const columnCount = Math.ceil(group.length / maximumRows);
            const totalGroupWidth = columnCount * targetWidth
                + Math.max(0, columnCount - 1) * targetGap;
            const desiredLeft = availableArea.width * group[0].centerX
                - totalGroupWidth / 2;
            const groupLeft = clamp(
                desiredLeft,
                screenMargin,
                Math.max(screenMargin, availableArea.width - screenMargin - totalGroupWidth),
            );

            for (let itemIndex = 0; itemIndex < group.length; itemIndex += 1) {
                const column = Math.floor(itemIndex / maximumRows);
                const firstInColumn = column * maximumRows;
                const rowsInColumn = Math.min(maximumRows, group.length - firstInColumn);
                const row = itemIndex - firstInColumn;
                const columnHeight = rowsInColumn * targetHeight
                    + Math.max(0, rowsInColumn - 1) * targetGap;
                const desiredTop = availableArea.height * group[itemIndex].centerY
                    - columnHeight / 2;
                const groupTop = clamp(
                    desiredTop,
                    screenMargin,
                    Math.max(screenMargin, availableArea.height - screenMargin - columnHeight),
                );
                const layout = group[itemIndex].layout;
                positioned.push({
                    actionId: layout.actionId,
                    name: layout.name,
                    x: layout.x,
                    y: layout.y,
                    width: layout.width,
                    height: layout.height,
                    kind: layout.kind,
                    groupKey: groupKeys[groupIndex],
                    centerX: group[itemIndex].centerX,
                    centerY: group[itemIndex].centerY,
                    targetX: Math.round(groupLeft + column * (targetWidth + targetGap)),
                    targetY: Math.round(groupTop + row * (targetHeight + targetGap)),
                });
            }
        }

        targets = positioned;
        revealedGroupKey = "";
        topTargetsRevealed = false;
        hoveredIndex = -1;
        hoveredPreview = Qt.rect(0, 0, 0, 0);
    }

    function activationRadius() {
        // Use logical pixels so the reveal distance remains comfortable on
        // both scaled high-DPI displays and smaller screens.
        return clamp(Math.min(availableArea.width, availableArea.height) * 0.14, 125, 210);
    }

    function cursorInsideRevealedGroup(localX, localY) {
        if (revealedGroupKey.length === 0) {
            return false;
        }

        let left = Number.POSITIVE_INFINITY;
        let top = Number.POSITIVE_INFINITY;
        let right = Number.NEGATIVE_INFINITY;
        let bottom = Number.NEGATIVE_INFINITY;
        for (let index = 0; index < targets.length; index += 1) {
            const target = targets[index];
            if (target.groupKey !== revealedGroupKey) {
                continue;
            }
            left = Math.min(left, target.targetX);
            top = Math.min(top, target.targetY);
            right = Math.max(right, target.targetX + targetWidth);
            bottom = Math.max(bottom, target.targetY + targetHeight);
        }

        return Number.isFinite(left)
            && localX >= left - revealedGroupPadding
            && localX <= right + revealedGroupPadding
            && localY >= top - revealedGroupPadding
            && localY <= bottom + revealedGroupPadding;
    }

    function cursorInsideTopStrip(localX, localY) {
        return topStripRect.width > 0
            && localX >= topStripRect.x
            && localX <= topStripRect.x + topStripRect.width
            && localY >= topStripRect.y
            && localY <= topStripRect.y + topStripRect.height;
    }

    function cursorNearTopCenter(localX, localY) {
        const triggerWidth = clamp(availableArea.width * 0.45, 420, 1000);
        const triggerHeight = clamp(availableArea.height * 0.10, 90, 160);
        const triggerLeft = (availableArea.width - triggerWidth) / 2;
        return localX >= triggerLeft
            && localX <= triggerLeft + triggerWidth
            && localY >= 0
            && localY <= triggerHeight;
    }

    function targetIsVisible(target) {
        if (targetPlacement === "top") {
            return showAllTopTargets || topTargetsRevealed;
        }
        return showAllTargets || target.groupKey === revealedGroupKey;
    }

    function nearestGroupForCursor(localX, localY) {
        const radiusSquared = activationRadius() * activationRadius();
        const checkedGroups = {};
        let nearestKey = "";
        let nearestDistance = Number.POSITIVE_INFINITY;
        for (let index = 0; index < targets.length; index += 1) {
            const target = targets[index];
            if (checkedGroups[target.groupKey]) {
                continue;
            }
            checkedGroups[target.groupKey] = true;

            const dx = localX - availableArea.width * target.centerX;
            const dy = localY - availableArea.height * target.centerY;
            const distance = dx * dx + dy * dy;
            if (distance <= radiusSquared && distance < nearestDistance) {
                nearestKey = target.groupKey;
                nearestDistance = distance;
            }
        }
        return nearestKey;
    }

    function areaForOutput(output) {
        if (!output) {
            return Qt.rect(0, 0, 0, 0);
        }

        const desktop = Workspace.currentDesktopForScreen(output)
            || Workspace.currentDesktop;
        const area = Workspace.clientArea(KWin.MaximizeArea, output, desktop);
        return Qt.rect(area.x, area.y, area.width, area.height);
    }

    function outputForCursor() {
        const cursor = Workspace.cursorPos;
        return Workspace.screenAt(cursor)
            || (dragWindow && !dragWindow.deleted ? dragWindow.output : null);
    }

    function finishOverlayRemap(revision) {
        if (revision !== mappingRevision || !dragActive) {
            return;
        }
        overlayMapped = true;
    }

    function refreshOutputForCursor(force = false) {
        const output = outputForCursor();
        const nextArea = areaForOutput(output);
        const areaChanged = force
            || currentOutput !== output
            || availableArea.x !== nextArea.x
            || availableArea.y !== nextArea.y
            || availableArea.width !== nextArea.width
            || availableArea.height !== nextArea.height;
        if (!areaChanged) {
            return;
        }

        currentOutput = output;
        availableArea = nextArea;
        rebuildTargets();

        // Plasma shell surfaces do not reliably migrate between Wayland
        // outputs while mapped. Remap after changing output geometry.
        overlayMapped = false;
        mappingRevision += 1;
        const revision = mappingRevision;
        Qt.callLater(() => finishOverlayRemap(revision));
    }

    function previewForLayout(layout) {
        if (!layout) {
            return Qt.rect(0, 0, 0, 0);
        }

        if (layout.kind === "center" && dragWindow && !dragWindow.deleted) {
            const geometry = dragWindow.frameGeometry;
            const width = Math.min(geometry.width, availableArea.width);
            const height = Math.min(geometry.height, availableArea.height);
            return Qt.rect(
                Math.round((availableArea.width - width) / 2),
                Math.round((availableArea.height - height) / 2),
                width,
                height,
            );
        }

        let left = Math.round(availableArea.width * layout.x);
        let top = Math.round(availableArea.height * layout.y);
        let right = Math.round(availableArea.width * (layout.x + layout.width));
        let bottom = Math.round(availableArea.height * (layout.y + layout.height));
        const edgeEpsilon = 0.000001;
        const horizontalInsets = constrainedInsets(
            right - left,
            layout.x > edgeEpsilon ? layoutPadding : 0,
            layout.x + layout.width < 1 - edgeEpsilon ? layoutPadding : 0,
        );
        const verticalInsets = constrainedInsets(
            bottom - top,
            layout.y > edgeEpsilon ? layoutPadding : 0,
            layout.y + layout.height < 1 - edgeEpsilon ? layoutPadding : 0,
        );
        left += horizontalInsets.start;
        right -= horizontalInsets.end;
        top += verticalInsets.start;
        bottom -= verticalInsets.end;
        return Qt.rect(left, top, Math.max(1, right - left), Math.max(1, bottom - top));
    }

    function updateHover() {
        if (!dragActive) {
            hoveredIndex = -1;
            hoveredPreview = Qt.rect(0, 0, 0, 0);
            return;
        }

        refreshOutputForCursor();
        const cursor = Workspace.cursorPos;
        const localX = cursor.x - availableArea.x;
        const localY = cursor.y - availableArea.y;
        if (targetPlacement === "top") {
            topTargetsRevealed = showAllTopTargets
                || (topTargetsRevealed && cursorInsideTopStrip(localX, localY))
                || cursorNearTopCenter(localX, localY);
        } else {
            topTargetsRevealed = false;
        }

        const nextGroup = targetPlacement === "top" || showAllTargets
            ? ""
            : (cursorInsideRevealedGroup(localX, localY)
                ? revealedGroupKey
                : nearestGroupForCursor(localX, localY));
        if (revealedGroupKey !== nextGroup) {
            revealedGroupKey = nextGroup;
        }

        let candidateIndex = -1;
        let shortestDistance = Number.POSITIVE_INFINITY;
        for (let index = 0; index < targets.length; index += 1) {
            const target = targets[index];
            if (!targetIsVisible(target)
                    || localX < target.targetX
                    || localX > target.targetX + targetWidth
                    || localY < target.targetY
                    || localY > target.targetY + targetHeight) {
                continue;
            }

            const dx = localX - (target.targetX + targetWidth / 2);
            const dy = localY - (target.targetY + targetHeight / 2);
            const distance = dx * dx + dy * dy;
            if (distance < shortestDistance) {
                candidateIndex = index;
                shortestDistance = distance;
            }
        }

        if (hoveredIndex !== candidateIndex) {
            hoveredIndex = candidateIndex;
        }
        hoveredPreview = candidateIndex >= 0
            ? previewForLayout(targets[candidateIndex])
            : Qt.rect(0, 0, 0, 0);
    }

    function beginDrag(window) {
        if (!window || window.deleted || window.resize) {
            return;
        }

        if (dragActive && dragWindow === window) {
            updateHover();
            return;
        }

        dragWindow = window;
        signalWindow = window;
        dragActive = true;
        revealedGroupKey = "";
        topTargetsRevealed = false;
        hoveredIndex = -1;
        hoveredPreview = Qt.rect(0, 0, 0, 0);
        refreshOutputForCursor(true);
        updateHover();
    }

    function invokeAction(actionId) {
        actionCall.arguments = [actionId];
        actionCall.call();
    }

    function finishDrag(applyHoveredLayout) {
        if (!dragActive) {
            return;
        }

        updateHover();
        const actionId = applyHoveredLayout && hoveredIndex >= 0
            ? targets[hoveredIndex].actionId
            : "";

        mappingRevision += 1;
        overlayMapped = false;
        dragActive = false;
        revealedGroupKey = "";
        topTargetsRevealed = false;
        hoveredIndex = -1;
        hoveredPreview = Qt.rect(0, 0, 0, 0);
        targets = [];
        dragWindow = null;

        if (actionId.length > 0) {
            // Let KWin finish the interactive move before invoking the normal
            // Window Layouts action. This also keeps Restore geometry working.
            Qt.callLater(() => invokeAction(actionId));
        }
    }

    function discoverInteractiveMove() {
        if (dragActive) {
            if (!dragWindow || dragWindow.deleted) {
                finishDrag(false);
                return;
            }
            if (dragWindow.move && !dragWindow.resize) {
                updateHover();
                return;
            }

            finishDrag(true);
            return;
        }

        if (isInteractiveMove(signalWindow)) {
            beginDrag(signalWindow);
            return;
        }

        const activeWindow = Workspace.activeWindow;
        if (isInteractiveMove(activeWindow)) {
            signalWindow = activeWindow;
            beginDrag(activeWindow);
            return;
        }

        // Signals and the active/signal windows cover normal moves. Keep a
        // slower all-window fallback for compositor versions that occasionally
        // miss the start signal, without walking every KWin window ten times a
        // second while the desktop is idle.
        idleFullScanCounter = (idleFullScanCounter + 1) % 4;
        if (idleFullScanCounter !== 0) {
            return;
        }

        // In KWin's declarative API this is a list property (the JavaScript
        // action API exposes a windowList() function instead).
        const windows = Workspace.windowList || [];
        for (let index = 0; index < windows.length; index += 1) {
            if (isInteractiveMove(windows[index])) {
                signalWindow = windows[index];
                beginDrag(windows[index]);
                return;
            }
        }
    }

    property Timer scanTimer: Timer {
        interval: controller.dragActive ? 32 : 125
        repeat: true
        running: true
        onTriggered: controller.discoverInteractiveMove()
    }

    property Connections workspaceConnections: Connections {
        target: Workspace
        ignoreUnknownSignals: true

        function onWindowActivated(window) {
            if (window && !window.deleted) {
                controller.signalWindow = window;
                if (controller.isInteractiveMove(window)) {
                    controller.beginDrag(window);
                }
            }
        }

        function onWindowRemoved(window) {
            if (controller.dragWindow === window) {
                controller.finishDrag(false);
            }
            if (controller.signalWindow === window) {
                controller.signalWindow = Workspace.activeWindow;
            }
        }

        function onScreensChanged() {
            if (controller.dragActive) {
                controller.refreshOutputForCursor(true);
                controller.updateHover();
            }
        }
    }

    property Connections windowConnections: Connections {
        target: controller.signalWindow
        ignoreUnknownSignals: true

        function onInteractiveMoveResizeStarted() {
            if (controller.signalWindow && !controller.signalWindow.resize) {
                controller.beginDrag(controller.signalWindow);
            }
        }

        function onInteractiveMoveResizeStepped(_geometry) {
            if (!controller.dragActive && controller.signalWindow
                    && !controller.signalWindow.resize) {
                controller.beginDrag(controller.signalWindow);
            }
            controller.updateHover();
        }

        function onInteractiveMoveResizeFinished() {
            if (controller.dragActive
                    && controller.dragWindow === controller.signalWindow) {
                controller.finishDrag(true);
            }
        }

        function onMoveResizedChanged() {
            if (controller.isInteractiveMove(controller.signalWindow)) {
                controller.beginDrag(controller.signalWindow);
            } else if (controller.dragActive
                    && controller.dragWindow === controller.signalWindow) {
                controller.finishDrag(!controller.signalWindow.resize);
            }
        }

        function onClosed() {
            if (controller.dragWindow === controller.signalWindow) {
                controller.finishDrag(false);
            }
        }
    }

    property Connections optionsConnections: Connections {
        target: Options
        ignoreUnknownSignals: true

        function onConfigChanged() {
            controller.loadFeatureSettings();
            if (controller.dragActive) {
                controller.rebuildTargets();
                controller.updateHover();
            }
        }
    }

    property DBusCall actionCall: DBusCall {
        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        method: "invokeShortcut"
    }

    property PlasmaCore.Dialog overlay: PlasmaCore.Dialog {
        id: overlayWindow

        title: "Window Layouts Drag Targets"
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.BypassWindowManagerHint
            | Qt.FramelessWindowHint
            | Qt.WindowDoesNotAcceptFocus
            | Qt.WindowTransparentForInput
            | Qt.Tool
        hideOnWindowDeactivate: false
        // Neither the whole overlay nor its delegates accepts pointer input.
        // Hover is derived from Workspace.cursorPos instead.
        outputOnly: true
        visible: controller.dragActive && controller.overlayMapped
        x: controller.availableArea.x
        y: controller.availableArea.y
        width: controller.availableArea.width
        height: controller.availableArea.height

        mainItem: Item {
            width: overlayWindow.width
            height: overlayWindow.height

            Rectangle {
                x: controller.hoveredPreview.x
                y: controller.hoveredPreview.y
                width: controller.hoveredPreview.width
                height: controller.hoveredPreview.height
                visible: controller.hoveredIndex >= 0
                color: "#403daee9"
                border.width: 3
                border.color: "#e63daee9"
                radius: 6
            }

            Rectangle {
                x: controller.topStripRect.x
                y: controller.topStripRect.y
                width: controller.topStripRect.width
                height: controller.topStripRect.height
                visible: controller.targetPlacement === "top"
                    && (controller.showAllTopTargets || controller.topTargetsRevealed)
                    && controller.topStripRect.width > 0
                color: "#b51a222c"
                border.width: 2
                border.color: controller.accentBlue
                radius: 12
            }

            Repeater {
                model: controller.targets

                delegate: Rectangle {
                    required property int index
                    required property var modelData

                    x: modelData.targetX
                    y: modelData.targetY
                    width: controller.targetWidth
                    height: controller.targetHeight
                    visible: controller.targetIsVisible(modelData)
                    radius: 9
                    color: index === controller.hoveredIndex
                        ? "#f01d2935"
                        : "#d91d2935"
                    border.width: index === controller.hoveredIndex ? 3 : 2
                    border.color: index === controller.hoveredIndex
                        ? "#ffffff"
                        : controller.accentBlue
                    opacity: index === controller.hoveredIndex ? 1 : 0.88

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 7
                        width: 70
                        height: 43

                        Rectangle {
                            anchors.fill: parent
                            color: "#45101820"
                            border.width: 1
                            border.color: "#d9c8d0d8"
                            radius: 2
                        }

                        Rectangle {
                            x: Math.round(parent.width * modelData.x)
                            y: Math.round(parent.height * modelData.y)
                            width: Math.max(2, Math.round(parent.width * modelData.width))
                            height: Math.max(2, Math.round(parent.height * modelData.height))
                            color: controller.accentBlue
                            border.width: 1
                            border.color: "#e6ffffff"
                            radius: 1
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        anchors.bottomMargin: 5
                        text: modelData.name
                        color: "white"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        loadFeatureSettings();
        signalWindow = Workspace.activeWindow;
        console.info("window-layouts-drag-overlay: Loaded input-transparent drag targets 1.0.0");
    }
}
