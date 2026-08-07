/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

const LOG_PREFIX = "window-layouts:";
const MAX_CUSTOM_LAYOUTS = 20;
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

const originalGeometry = new Map();
const watchedWindows = new Map();
let lastActiveWindow = null;
let customLayouts = [];

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

function rectangleForLayout(area, layout) {
    const left = Math.round(area.x + area.width * layout.x);
    const top = Math.round(area.y + area.height * layout.y);
    const right = Math.round(area.x + area.width * (layout.x + layout.width));
    const bottom = Math.round(area.y + area.height * (layout.y + layout.height));

    return {
        x: left,
        y: top,
        width: Math.max(1, right - left),
        height: Math.max(1, bottom - top),
    };
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

    customLayouts = parsedLayouts
        .slice(0, MAX_CUSTOM_LAYOUTS)
        .map(validatedCustomLayout)
        .filter(layout => layout !== null);

    log(`Loaded ${customLayouts.length} custom layout(s)`);
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

    let currentIndex = outputs.indexOf(window.output);
    if (currentIndex < 0) {
        currentIndex = 0;
    }

    rememberOriginalGeometry(window);
    const targetOutput = outputs[wrappedIndex(currentIndex, offset, outputs.length)];
    workspace.sendClientToScreen(window, targetOutput);
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

loadCustomLayouts();

for (const layout of layouts) {
    registerShortcut(
        layout.actionId,
        `Window Layouts: ${layout.name}`,
        "",
        () => applyLayout(layout),
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
            if (customLayouts[index]) {
                applyLayout(customLayouts[index]);
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
            title: layout.name,
            triggered: () => applyLayout(layout, window),
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
options.configChanged.connect(loadCustomLayouts);

log("Loaded window layouts");
