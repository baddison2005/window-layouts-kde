#!/usr/bin/env node

/* SPDX-License-Identifier: GPL-2.0-or-later */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const desktop = { id: "desktop-1" };
const otherDesktop = { id: "desktop-2" };
const output = { name: "primary" };
const otherOutput = { name: "secondary" };

function rectangle(x, y, width = 200, height = 150) {
    return { x, y, width, height };
}

function assertRectangle(actual, expected) {
    assert.deepEqual({
        x: actual.x,
        y: actual.y,
        width: actual.width,
        height: actual.height,
    }, expected);
}

function mockWindow(name, geometry, overrides = {}) {
    return {
        caption: name,
        deleted: false,
        managed: true,
        normalWindow: true,
        moveable: true,
        resizeable: true,
        minimized: false,
        fullScreen: false,
        onAllDesktops: false,
        desktops: [desktop],
        activities: ["activity-1"],
        output,
        frameGeometry: { ...geometry },
        closed: { connect() {} },
        setMaximize() {},
        ...overrides,
    };
}

const front = mockWindow("front", rectangle(10, 20));
const second = mockWindow("second", rectangle(30, 40));
const third = mockWindow("third", rectangle(50, 60));
const fourth = mockWindow("fourth", rectangle(70, 80));
const minimized = mockWindow("minimized", rectangle(90, 100), { minimized: true });
const fullscreen = mockWindow("fullscreen", rectangle(110, 120), { fullScreen: true });
const wrongDisplay = mockWindow("wrong-display", rectangle(130, 140), { output: otherOutput });
const wrongDesktop = mockWindow("wrong-desktop", rectangle(150, 160), { desktops: [otherDesktop] });
const wrongActivity = mockWindow("wrong-activity", rectangle(170, 180), { activities: ["activity-2"] });

// KWin's stackingOrder is bottom-to-top.
const windows = [
    wrongActivity,
    wrongDesktop,
    wrongDisplay,
    fullscreen,
    minimized,
    fourth,
    third,
    second,
    front,
];
const shortcuts = new Map();
const customGroups = [{
    id: "pair",
    name: "Pair",
    fillShortcutSlot: 7,
}];
const customLayouts = [
    { name: "Top", x: 0, y: 0, width: 1, height: 0.5, shortcutSlot: 1, groupId: "pair" },
    { name: "Bottom", x: 0, y: 0.5, width: 1, height: 0.5, shortcutSlot: 2, groupId: "pair" },
];

const context = {
    console: { info() {} },
    KWin: { MaximizeArea: 1 },
    workspace: {
        activeWindow: front,
        currentActivity: "activity-1",
        currentDesktop: desktop,
        stackingOrder: windows,
        windowActivated: { connect() {} },
        windowList: () => windows,
        currentDesktopForScreen: () => desktop,
        clientArea: () => ({ x: 0, y: 0, width: 1200, height: 900 }),
    },
    options: { configChanged: { connect() {} } },
    readConfig(key, fallback) {
        if (key === "CustomGroups") {
            return JSON.stringify(customGroups);
        }
        if (key === "CustomLayouts") {
            return JSON.stringify(customLayouts);
        }
        return fallback;
    },
    registerShortcut(actionId, _name, _defaultKey, callback) {
        shortcuts.set(actionId, callback);
    },
    registerUserActionsMenu() {},
    callDBus() {},
};

const scriptPath = path.join(
    __dirname,
    "..",
    "packages",
    "kwin-script",
    "contents",
    "code",
    "main.js",
);
vm.runInNewContext(fs.readFileSync(scriptPath, "utf8"), context, {
    filename: scriptPath,
});

assert.ok(shortcuts.has("WindowLayoutsFillThirds"));
assert.ok(shortcuts.has("WindowLayoutsFillCustomGroup7"));

shortcuts.get("WindowLayoutsFillThirds")();
assertRectangle(front.frameGeometry, { x: 0, y: 0, width: 400, height: 900 });
assertRectangle(second.frameGeometry, { x: 400, y: 0, width: 400, height: 900 });
assertRectangle(third.frameGeometry, { x: 800, y: 0, width: 400, height: 900 });
assertRectangle(fourth.frameGeometry, { x: 0, y: 0, width: 400, height: 900 });

for (const excluded of [minimized, fullscreen, wrongDisplay, wrongDesktop, wrongActivity]) {
    assert.notDeepEqual(excluded.frameGeometry, { x: 0, y: 0, width: 400, height: 900 });
}

shortcuts.get("WindowLayoutsRestore")();
assertRectangle(front.frameGeometry, rectangle(10, 20));

shortcuts.get("WindowLayoutsFillCustomGroup7")();
assertRectangle(front.frameGeometry, { x: 0, y: 0, width: 1200, height: 450 });
assertRectangle(second.frameGeometry, { x: 0, y: 450, width: 1200, height: 450 });
assertRectangle(third.frameGeometry, { x: 0, y: 0, width: 1200, height: 450 });

process.stdout.write("KWin fill-display tests passed\n");
