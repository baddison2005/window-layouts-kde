/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

const LOG_PREFIX = "window-layouts:";
const MAX_CUSTOM_LAYOUTS = 20;
const MAX_CUSTOM_GROUPS = 20;
const MAX_LAYOUT_PADDING = 200;
const LAYOUT_EDGE_EPSILON = 0.000001;
const GEOMETRY_MATCH_TOLERANCE = 3;
const CONFIGURATOR_SERVICE = "org.example.WindowLayouts.Configurator";
const CONFIGURATOR_PATH = "/org/example/WindowLayouts/Configurator";
const CONFIGURATOR_INTERFACE = "org.example.WindowLayouts.Configurator";

// Keep these action IDs in sync with the model in the Plasmoid's main.qml.
const layouts = [
    { actionId: "WindowLayoutsLeftHalf", name: "Left Half", x: 0, y: 0, width: 1 / 2, height: 1 },
    { actionId: "WindowLayoutsRightHalf", name: "Right Half", x: 1 / 2, y: 0, width: 1 / 2, height: 1 },
    { actionId: "WindowLayoutsTopHalf", name: "Top Half", x: 0, y: 0, width: 1, height: 1 / 2 },
    { actionId: "WindowLayoutsBottomHalf", name: "Bottom Half", x: 0, y: 1 / 2, width: 1, height: 1 / 2 },

    { actionId: "WindowLayoutsTopLeft", name: "Top Left", x: 0, y: 0, width: 1 / 2, height: 1 / 2 },
    { actionId: "WindowLayoutsTopRight", name: "Top Right", x: 1 / 2, y: 0, width: 1 / 2, height: 1 / 2 },
    { actionId: "WindowLayoutsBottomLeft", name: "Bottom Left", x: 0, y: 1 / 2, width: 1 / 2, height: 1 / 2 },
    { actionId: "WindowLayoutsBottomRight", name: "Bottom Right", x: 1 / 2, y: 1 / 2, width: 1 / 2, height: 1 / 2 },

    { actionId: "WindowLayoutsLeftThird", name: "Left Third", x: 0, y: 0, width: 1 / 3, height: 1 },
    { actionId: "WindowLayoutsCenterThird", name: "Center Third", x: 1 / 3, y: 0, width: 1 / 3, height: 1 },
    { actionId: "WindowLayoutsRightThird", name: "Right Third", x: 2 / 3, y: 0, width: 1 / 3, height: 1 },

    { actionId: "WindowLayoutsLeftTwoThirds", name: "Left Two Thirds", x: 0, y: 0, width: 2 / 3, height: 1 },
    { actionId: "WindowLayoutsCenterTwoThirds", name: "Center Two Thirds", x: 1 / 6, y: 0, width: 2 / 3, height: 1 },
    { actionId: "WindowLayoutsRightTwoThirds", name: "Right Two Thirds", x: 1 / 3, y: 0, width: 2 / 3, height: 1 },
];

// A fill group applies these layouts to all eligible visible windows on the
// active window's display. Keep the IDs stable: KDE stores shortcuts by ID.
const builtInFillGroups = [
    {
        actionId: "WindowLayoutsFillHorizontalHalves",
        name: "Horizontal Halves",
        layouts: [layouts[0], layouts[1]],
    },
    {
        actionId: "WindowLayoutsFillVerticalHalves",
        name: "Vertical Halves",
        layouts: [layouts[2], layouts[3]],
    },
    {
        actionId: "WindowLayoutsFillQuarters",
        name: "Quarters",
        layouts: [layouts[4], layouts[5], layouts[6], layouts[7]],
    },
    {
        actionId: "WindowLayoutsFillThirds",
        name: "Thirds",
        layouts: [layouts[8], layouts[9], layouts[10]],
    },
];

const originalGeometry = new Map();
const watchedWindows = new Map();
let lastActiveWindow = null;
let customLayouts = [];
let customGroups = {};
let customGroupList = [];
let layoutPadding = 0;

function log(message) {
    console.info(`${LOG_PREFIX} ${message}`);
}

function isEligibleWindow(window) {
    return window
        && !window.deleted
        && window.managed
        && window.normalWindow
        && window.moveable
        && window.resizeable;
}

function copyRectangle(rectangle) {
    return {
        x: rectangle.x,
        y: rectangle.y,
        width: rectangle.width,
        height: rectangle.height,
    };
}

function watchWindow(window) {
    if (!window || watchedWindows.has(window)) {
        return;
    }

    watchedWindows.set(window, true);
    window.closed.connect(() => {
        watchedWindows.delete(window);
        originalGeometry.delete(window);
        if (lastActiveWindow === window) {
            lastActiveWindow = null;
        }
    });
}

function rememberWindow(window) {
    watchWindow(window);
    if (isEligibleWindow(window)) {
        lastActiveWindow = window;
    }
}

function targetWindow(preferredWindow) {
    if (isEligibleWindow(preferredWindow)) {
        return preferredWindow;
    }

    if (isEligibleWindow(workspace.activeWindow)) {
        return workspace.activeWindow;
    }

    if (isEligibleWindow(lastActiveWindow)) {
        return lastActiveWindow;
    }

    log("No moveable and resizeable application window is active");
    return null;
}

function rememberOriginalGeometry(window) {
    if (!originalGeometry.has(window)) {
        originalGeometry.set(window, copyRectangle(window.frameGeometry));
    }
}

function leaveSpecialWindowStates(window) {
    if (window.fullScreen) {
        window.fullScreen = false;
    }
    window.setMaximize(false, false);
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

function rectangleForLayout(area, layout, applyPadding = true) {
    let left = Math.round(area.x + area.width * layout.x);
    let top = Math.round(area.y + area.height * layout.y);
    let right = Math.round(area.x + area.width * (layout.x + layout.width));
    let bottom = Math.round(area.y + area.height * (layout.y + layout.height));

    // Keep edges that coincide with the usable monitor boundary flush. Every
    // internal edge is inset by the configured number of logical pixels.
    const horizontalInsets = constrainedInsets(
        right - left,
        applyPadding && layout.x > LAYOUT_EDGE_EPSILON ? layoutPadding : 0,
        applyPadding && layout.x + layout.width < 1 - LAYOUT_EDGE_EPSILON
            ? layoutPadding
            : 0,
    );
    const verticalInsets = constrainedInsets(
        bottom - top,
        applyPadding && layout.y > LAYOUT_EDGE_EPSILON ? layoutPadding : 0,
        applyPadding && layout.y + layout.height < 1 - LAYOUT_EDGE_EPSILON
            ? layoutPadding
            : 0,
    );
    left += horizontalInsets.start;
    right -= horizontalInsets.end;
    top += verticalInsets.start;
    bottom -= verticalInsets.end;

    return {
        x: left,
        y: top,
        width: Math.max(1, right - left),
        height: Math.max(1, bottom - top),
    };
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(value, maximum));
}

function normalizedGeometry(area, geometry) {
    if (area.width <= 0 || area.height <= 0) {
        return { x: 0, y: 0, width: 1, height: 1 };
    }

    const width = clamp(geometry.width / area.width, 1 / area.width, 1);
    const height = clamp(geometry.height / area.height, 1 / area.height, 1);
    const x = clamp((geometry.x - area.x) / area.width, 0, 1 - width);
    const y = clamp((geometry.y - area.y) / area.height, 0, 1 - height);
    return { x, y, width, height };
}

function rectanglesApproximatelyEqual(first, second, tolerance = GEOMETRY_MATCH_TOLERANCE) {
    return Math.abs(first.x - second.x) <= tolerance
        && Math.abs(first.y - second.y) <= tolerance
        && Math.abs(first.width - second.width) <= tolerance
        && Math.abs(first.height - second.height) <= tolerance;
}

function matchingLayout(area, geometry) {
    const candidates = layouts.concat(customLayouts);
    for (const layout of candidates) {
        if (rectanglesApproximatelyEqual(
            rectangleForLayout(area, layout),
            geometry,
        )) {
            return layout;
        }
    }
    return null;
}

function isFiniteNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
}

function validatedCustomLayout(candidate, index) {
    if (!candidate || typeof candidate !== "object") {
        return null;
    }

    const x = candidate.x;
    const y = candidate.y;
    const width = candidate.width;
    const height = candidate.height;
    if (!isFiniteNumber(x)
        || !isFiniteNumber(y)
        || !isFiniteNumber(width)
        || !isFiniteNumber(height)
        || x < 0
        || y < 0
        || width <= 0
        || height <= 0
        || x + width > 1.000001
        || y + height > 1.000001) {
        return null;
    }

    const configuredName = typeof candidate.name === "string"
        ? candidate.name.trim()
        : "";

    return {
        name: configuredName || `Custom Layout ${index + 1}`,
        x,
        y,
        width,
        height,
        shortcutSlot: Number.isInteger(candidate.shortcutSlot)
            && candidate.shortcutSlot >= 1
            && candidate.shortcutSlot <= MAX_CUSTOM_LAYOUTS
                ? candidate.shortcutSlot
                : index + 1,
        groupId: typeof candidate.groupId === "string" ? candidate.groupId : "",
    };
}

function loadCustomLayouts() {
    const configuredValue = readConfig("CustomLayouts", "[]");
    let parsedLayouts;

    try {
        parsedLayouts = JSON.parse(String(configuredValue));
    } catch (error) {
        customLayouts = [];
        log(`Could not parse custom layouts: ${error}`);
        return;
    }

    if (!Array.isArray(parsedLayouts)) {
        customLayouts = [];
        log("Custom layout configuration is not an array");
        return;
    }

    const usedSlots = [];
    customLayouts = parsedLayouts
        .slice(0, MAX_CUSTOM_LAYOUTS)
        .map(validatedCustomLayout)
        .filter(layout => layout !== null)
        .map(layout => {
            if (usedSlots.indexOf(layout.shortcutSlot) >= 0) {
                for (let slot = 1; slot <= MAX_CUSTOM_LAYOUTS; slot += 1) {
                    if (usedSlots.indexOf(slot) < 0) {
                        layout.shortcutSlot = slot;
                        break;
                    }
                }
            }
            usedSlots.push(layout.shortcutSlot);
            return layout;
        });

    customGroups = {};
    customGroupList = [];
    try {
        const parsedGroups = JSON.parse(String(readConfig("CustomGroups", "[]")));
        if (Array.isArray(parsedGroups)) {
            const usedFillSlots = [];
            for (const group of parsedGroups) {
                if (group
                        && typeof group.id === "string"
                        && group.id.length > 0
                        && typeof group.name === "string"
                        && group.name.trim().length > 0
                        && customGroups[group.id] === undefined) {
                    let fillShortcutSlot = Number.isInteger(group.fillShortcutSlot)
                        && group.fillShortcutSlot >= 1
                        && group.fillShortcutSlot <= MAX_CUSTOM_GROUPS
                        && usedFillSlots.indexOf(group.fillShortcutSlot) < 0
                            ? group.fillShortcutSlot
                            : -1;
                    if (fillShortcutSlot < 0) {
                        for (let slot = 1; slot <= MAX_CUSTOM_GROUPS; slot += 1) {
                            if (usedFillSlots.indexOf(slot) < 0) {
                                fillShortcutSlot = slot;
                                break;
                            }
                        }
                    }
                    const name = group.name.trim();
                    usedFillSlots.push(fillShortcutSlot);
                    customGroups[group.id] = name;
                    customGroupList.push({
                        id: group.id,
                        name,
                        fillShortcutSlot,
                    });
                }
            }
        }
    } catch (error) {
        log(`Could not parse custom groups: ${error}`);
    }

    log(`Loaded ${customLayouts.length} custom layout(s)`);
}

function windowIsOnDesktop(window, desktop) {
    if (window.onAllDesktops || !window.desktops || window.desktops.length === 0) {
        return true;
    }
    return window.desktops.indexOf(desktop) >= 0;
}

function windowIsOnActivity(window, activity) {
    if (!activity || !window.activities || window.activities.length === 0) {
        return true;
    }
    return window.activities.indexOf(activity) >= 0;
}

function eligibleVisibleWindows(anchor) {
    const output = anchor.output;
    const desktop = workspace.currentDesktopForScreen(output)
        || workspace.currentDesktop;
    const activity = workspace.currentActivity;
    const candidates = [];
    const stackingOrder = workspace.stackingOrder || workspace.windowList();

    // KWin exposes stackingOrder from bottom to top. Iterate backwards so the
    // frontmost window receives the first layout, matching the macOS version.
    for (let index = stackingOrder.length - 1; index >= 0; index -= 1) {
        const window = stackingOrder[index];
        if (!isEligibleWindow(window)
                || window.minimized
                || window.fullScreen
                || window.output !== output
                || !windowIsOnDesktop(window, desktop)
                || !windowIsOnActivity(window, activity)
                || candidates.indexOf(window) >= 0) {
            continue;
        }
        candidates.push(window);
    }
    return candidates;
}

function fillDisplayWithLayouts(fillLayouts, preferredWindow = null) {
    const anchor = targetWindow(preferredWindow);
    if (!anchor || anchor.minimized || anchor.fullScreen || fillLayouts.length === 0) {
        log("Fill display requires a visible, non-full-screen active window and a non-empty layout group");
        return;
    }

    const windows = eligibleVisibleWindows(anchor);
    if (windows.length === 0) {
        log("No eligible visible windows found on the active display");
        return;
    }

    const targetArea = workspace.clientArea(KWin.MaximizeArea, anchor);
    for (let index = 0; index < windows.length; index += 1) {
        const window = windows[index];
        rememberOriginalGeometry(window);
        leaveSpecialWindowStates(window);
        window.frameGeometry = rectangleForLayout(
            targetArea,
            fillLayouts[index % fillLayouts.length],
        );
    }
    lastActiveWindow = anchor;
    log(`Filled active display with ${windows.length} window(s) across ${fillLayouts.length} layout(s)`);
}

function customFillLayouts(groupId) {
    return customLayouts.filter(layout => layout.groupId === groupId);
}

function loadConfiguration() {
    loadCustomLayouts();
    const configuredPadding = Number(readConfig("LayoutPadding", 0));
    layoutPadding = Number.isFinite(configuredPadding)
        ? clamp(Math.round(configuredPadding), 0, MAX_LAYOUT_PADDING)
        : 0;
    log(`Using ${layoutPadding}px layout padding`);
}

function applyLayout(layout, preferredWindow = null) {
    const window = targetWindow(preferredWindow);
    if (!window) {
        return;
    }

    rememberOriginalGeometry(window);
    leaveSpecialWindowStates(window);

    // MaximizeArea accounts for panels and is resolved for the window's output.
    const area = workspace.clientArea(KWin.MaximizeArea, window);
    window.frameGeometry = rectangleForLayout(area, layout);
    lastActiveWindow = window;
}

function maximizeWindow(preferredWindow = null) {
    const window = targetWindow(preferredWindow);
    if (!window) {
        return;
    }

    rememberOriginalGeometry(window);
    if (window.fullScreen) {
        window.fullScreen = false;
    }
    window.setMaximize(true, true);
    lastActiveWindow = window;
}

function centerWindow(preferredWindow = null) {
    const window = targetWindow(preferredWindow);
    if (!window) {
        return;
    }

    rememberOriginalGeometry(window);
    leaveSpecialWindowStates(window);

    const area = workspace.clientArea(KWin.MaximizeArea, window);
    const geometry = window.frameGeometry;
    const width = Math.min(geometry.width, area.width);
    const height = Math.min(geometry.height, area.height);

    window.frameGeometry = {
        x: Math.round(area.x + (area.width - width) / 2),
        y: Math.round(area.y + (area.height - height) / 2),
        width,
        height,
    };
    lastActiveWindow = window;
}

function restoreWindow(preferredWindow = null) {
    const window = targetWindow(preferredWindow);
    if (!window) {
        return;
    }

    const geometry = originalGeometry.get(window);
    if (!geometry) {
        log(`No saved geometry for ${window.caption}`);
        return;
    }

    leaveSpecialWindowStates(window);
    window.frameGeometry = geometry;
    originalGeometry.delete(window);
    lastActiveWindow = window;
}

function wrappedIndex(index, offset, length) {
    return (index + offset + length) % length;
}

function moveToAdjacentMonitor(offset, preferredWindow = null) {
    const window = targetWindow(preferredWindow);
    if (!window) {
        return;
    }

    const outputs = workspace.screenOrder;
    if (!outputs || outputs.length < 2) {
        log("There is no second monitor to move the window to");
        return;
    }

    const sourceOutput = window.output;
    let currentIndex = outputs.indexOf(sourceOutput);
    if (currentIndex < 0) {
        currentIndex = 0;
    }

    const targetOutput = outputs[wrappedIndex(currentIndex, offset, outputs.length)];
    const sourceArea = workspace.clientArea(KWin.MaximizeArea, window);
    const sourceGeometry = copyRectangle(window.frameGeometry);
    const sourceLayout = matchingLayout(sourceArea, sourceGeometry);
    const relativeGeometry = sourceLayout
        ? null
        : normalizedGeometry(sourceArea, sourceGeometry);
    const fillsSourceArea = rectanglesApproximatelyEqual(
        sourceArea,
        sourceGeometry,
    );

    rememberOriginalGeometry(window);
    workspace.sendClientToScreen(window, targetOutput);

    // KWin keeps full-screen and maximized windows in their special state.
    // Normal windows are explicitly rescaled into the destination's usable
    // area, including its resolution, scaling, panels, and global position.
    if (!window.fullScreen && !fillsSourceArea) {
        const targetDesktop = workspace.currentDesktopForScreen(targetOutput)
            || workspace.currentDesktop;
        const targetArea = workspace.clientArea(
            KWin.MaximizeArea,
            targetOutput,
            targetDesktop,
        );
        window.frameGeometry = rectangleForLayout(
            targetArea,
            sourceLayout || relativeGeometry,
            sourceLayout !== null,
        );
    }
    lastActiveWindow = window;
}

function moveToPreviousMonitor(preferredWindow = null) {
    moveToAdjacentMonitor(-1, preferredWindow);
}

function moveToNextMonitor(preferredWindow = null) {
    moveToAdjacentMonitor(1, preferredWindow);
}

function moveToAdjacentWorkspace(offset, preferredWindow = null) {
    const window = targetWindow(preferredWindow);
    if (!window) {
        return;
    }

    const desktops = workspace.desktops;
    if (!desktops || desktops.length < 2) {
        log("There is no second workspace to move the window to");
        return;
    }

    const currentDesktop = workspace.currentDesktopForScreen(window.output)
        || workspace.currentDesktop;
    let currentIndex = desktops.indexOf(currentDesktop);
    if (currentIndex < 0) {
        currentIndex = 0;
    }

    const targetDesktop = desktops[wrappedIndex(currentIndex, offset, desktops.length)];
    window.desktops = [targetDesktop];
    workspace.setCurrentDesktopForScreen(targetDesktop, window.output);
    lastActiveWindow = window;
}

function moveToPreviousWorkspace(preferredWindow = null) {
    moveToAdjacentWorkspace(-1, preferredWindow);
}

function moveToNextWorkspace(preferredWindow = null) {
    moveToAdjacentWorkspace(1, preferredWindow);
}

function openConfigurator() {
    callDBus(
        CONFIGURATOR_SERVICE,
        CONFIGURATOR_PATH,
        CONFIGURATOR_INTERFACE,
        "Show",
    );
}

loadConfiguration();

for (const layout of layouts) {
    registerShortcut(
        layout.actionId,
        `Window Layouts: ${layout.name}`,
        "",
        () => applyLayout(layout),
    );
}

for (const fillGroup of builtInFillGroups) {
    registerShortcut(
        fillGroup.actionId,
        `Window Layouts: Fill Display — ${fillGroup.name}`,
        "",
        () => fillDisplayWithLayouts(fillGroup.layouts),
    );
}

// Global shortcut registrations cannot be added and removed dynamically, so
// reserve a small set of stable slots. Each callback resolves its layout at
// invocation time and therefore picks up configuration changes immediately.
for (let index = 0; index < MAX_CUSTOM_LAYOUTS; index += 1) {
    registerShortcut(
        `WindowLayoutsCustom${index + 1}`,
        `Window Layouts: Custom ${index + 1}`,
        "",
        () => {
            const layout = customLayouts.find(candidate => candidate.shortcutSlot === index + 1);
            if (layout) {
                applyLayout(layout);
            }
        },
    );
}

// Custom group actions use stable reserved slots for the same reason as
// custom layouts. Renaming or reordering a group does not invalidate its key.
for (let index = 0; index < MAX_CUSTOM_GROUPS; index += 1) {
    registerShortcut(
        `WindowLayoutsFillCustomGroup${index + 1}`,
        `Window Layouts: Fill Display — Custom Group ${index + 1}`,
        "",
        () => {
            const group = customGroupList.find(
                candidate => candidate.fillShortcutSlot === index + 1,
            );
            if (group) {
                fillDisplayWithLayouts(customFillLayouts(group.id));
            }
        },
    );
}

registerShortcut(
    "WindowLayoutsMaximize",
    "Window Layouts: Maximize",
    "",
    () => maximizeWindow(),
);

registerShortcut(
    "WindowLayoutsCenter",
    "Window Layouts: Center",
    "",
    () => centerWindow(),
);

registerShortcut(
    "WindowLayoutsRestore",
    "Window Layouts: Restore",
    "",
    () => restoreWindow(),
);

registerShortcut(
    "WindowLayoutsPreviousWorkspace",
    "Window Layouts: Move to Previous Workspace",
    "",
    () => moveToPreviousWorkspace(),
);

registerShortcut(
    "WindowLayoutsNextWorkspace",
    "Window Layouts: Move to Next Workspace",
    "",
    () => moveToNextWorkspace(),
);

registerShortcut(
    "WindowLayoutsPreviousMonitor",
    "Window Layouts: Move to Previous Monitor",
    "",
    () => moveToPreviousMonitor(),
);

registerShortcut(
    "WindowLayoutsNextMonitor",
    "Window Layouts: Move to Next Monitor",
    "",
    () => moveToNextMonitor(),
);

registerShortcut(
    "WindowLayoutsConfigure",
    "Window Layouts: Configure",
    "",
    openConfigurator,
);

// Also expose the layouts through Alt+F3 and the decoration context menu.
registerUserActionsMenu(window => ({
    title: "Window Layouts",
    items: [
        ...layouts.map(layout => ({
            title: layout.name,
            triggered: () => applyLayout(layout, window),
        })),
        ...customLayouts.map(layout => ({
            title: customGroups[layout.groupId]
                ? `${customGroups[layout.groupId]} — ${layout.name}`
                : layout.name,
            triggered: () => applyLayout(layout, window),
        })),
        {
            title: "Fill Display — Horizontal Halves",
            triggered: () => fillDisplayWithLayouts(builtInFillGroups[0].layouts, window),
        },
        {
            title: "Fill Display — Vertical Halves",
            triggered: () => fillDisplayWithLayouts(builtInFillGroups[1].layouts, window),
        },
        {
            title: "Fill Display — Quarters",
            triggered: () => fillDisplayWithLayouts(builtInFillGroups[2].layouts, window),
        },
        {
            title: "Fill Display — Thirds",
            triggered: () => fillDisplayWithLayouts(builtInFillGroups[3].layouts, window),
        },
        ...customGroupList
            .filter(group => customFillLayouts(group.id).length > 0)
            .map(group => ({
                title: `Fill Display — ${group.name}`,
                triggered: () => fillDisplayWithLayouts(
                    customFillLayouts(group.id),
                    window,
                ),
            })),
        {
            title: "Maximize",
            triggered: () => maximizeWindow(window),
        },
        {
            title: "Center",
            triggered: () => centerWindow(window),
        },
        {
            title: "Restore",
            triggered: () => restoreWindow(window),
        },
        {
            title: "Move to Previous Workspace",
            triggered: () => moveToPreviousWorkspace(window),
        },
        {
            title: "Move to Next Workspace",
            triggered: () => moveToNextWorkspace(window),
        },
        {
            title: "Move to Previous Monitor",
            triggered: () => moveToPreviousMonitor(window),
        },
        {
            title: "Move to Next Monitor",
            triggered: () => moveToNextMonitor(window),
        },
        {
            title: "Configure…",
            triggered: openConfigurator,
        },
    ],
}));

workspace.windowList().forEach(watchWindow);
workspace.windowActivated.connect(rememberWindow);
rememberWindow(workspace.activeWindow);
options.configChanged.connect(loadConfiguration);

log("Loaded window layouts");
