#!/usr/bin/env node
/* SPDX-License-Identifier: GPL-2.0-or-later */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

function signal() {
    const callbacks = [];
    return { connect(fn) { callbacks.push(fn); }, emit(...args) { callbacks.forEach(fn => fn(...args)); } };
}
const source = fs.readFileSync(path.join(__dirname, "../packages/kwin-script/contents/code/main.js"), "utf8");
function setup({ existing = [], custom = [], asyncDBus = false, arm = true } = {}) {
    let now = 0;
    let rules = [{ applicationId: "org.example.Editor", applicationName: "Editor", wmClass: "Editor",
        layoutId: "WindowLayoutsRightHalf", monitor: "DP-2", windowRequirement: "documentWindow",
        titleIncludes: "", excludedTitles: ["Getting Started"] }];
    const outputs = [{ name: "DP-1" }, { name: "DP-2" }];
    const windows = [...existing];
    const alive = new Set(existing.map(window => `${window.pid}:1`));
    const requests = [];
    const timers = [];
    class Timer {
        constructor() { this.timeout = signal(); timers.push(this); }
        start() { this.running = true; }
        stop() { this.running = false; }
    }
    const workspace = {
        windowAdded: signal(), windowActivated: signal(), activeWindow: null,
        windowList: () => windows, screenOrder: outputs, currentDesktop: {},
        currentDesktopForScreen: () => ({}),
        sendClientToScreen(window, output) { window.output = output; },
        clientArea(_type, output) { return output === outputs[1]
            ? { x: 1920, y: 30, width: 1600, height: 870 }
            : { x: 0, y: 30, width: 1920, height: 1050 }; },
    };
    const context = {
        console: { info() {} }, Date: { now: () => now }, QTimer: Timer,
        KWin: { MaximizeArea: 1 }, workspace, options: { configChanged: signal() },
        readConfig(key, fallback) {
            if (key === "ApplicationMappings") return JSON.stringify(rules);
            if (key === "CustomLayouts") return JSON.stringify(custom);
            if (key === "LayoutPadding") return 10;
            return fallback;
        },
        registerShortcut() {}, registerUserActionsMenu() {},
        callDBus(_service, _path, _interface, method, pid, previous, callback) {
            assert.equal(method, "InspectLaunchProcess");
            const respond = () => {
                const tokens = JSON.parse(previous).filter(token => alive.has(token));
                const token = alive.has(`${pid}:1`) ? `${pid}:1` : "";
                const previousAlive = tokens.length > 0;
                if (token && !tokens.includes(token)) tokens.push(token);
                callback(JSON.stringify({ token, previousAlive, processes: tokens }));
            };
            if (asyncDBus) requests.push(respond); else respond();
        },
    };
    vm.createContext(context);
    vm.runInContext(source, context);
    function tick(ms = 1500) {
        now += ms;
        timers.forEach(timer => { if (timer.running) timer.timeout.emit(); });
    }
    function add(window) {
        windows.push(window);
        alive.add(`${window.pid}:1`);
        workspace.windowAdded.emit(window);
    }
    function close(window) {
        window.closed.emit();
        window.deleted = true;
        windows.splice(windows.indexOf(window), 1);
    }
    function settle() { tick(); tick(); }
    function config(patch) {
        rules = [{ ...rules[0], ...patch }];
        context.options.configChanged.emit();
    }
    if (arm) tick(31000);
    return { add, close, tick, settle, alive, outputs, config, requests, workspace };
}
const initial = { x: 10, y: 50, width: 700, height: 500 };
function window(pid, caption, overrides = {}) {
    return { pid, caption, desktopFileName: "org.example.Editor", resourceClass: "Editor",
        managed: true, normalWindow: true, moveable: true, resizeable: true, readyForPainting: true,
        frameGeometry: { ...initial }, closed: signal(), setMaximize() {}, ...overrides };
}
function unchanged(window) { assert.deepEqual({ ...window.frameGeometry }, initial); }
function placed(window) {
    assert.deepEqual({ ...window.frameGeometry }, { x: 2730, y: 30, width: 790, height: 870 });
}

// A splash/launcher and a chooser never consume the mapping; a later document does.
{
    const app = setup();
    const launcher = window(100, "Welcome — Editor");
    app.add(launcher); app.settle(); unchanged(launcher);
    const chooser = window(100, "Open File", { dialog: true });
    app.add(chooser); app.settle(); unchanged(chooser);
    app.close(launcher); app.close(chooser);
    const doc = window(100, "budget.ods — Editor");
    app.add(doc); app.settle(); placed(doc);
    const second = window(100, "other.ods — Editor");
    app.add(second); app.settle(); unchanged(second);
    app.close(doc); app.close(second);
    // Closing every window without exiting the process must not rearm it.
    const third = window(100, "third.ods — Editor");
    app.add(third); app.settle(); unchanged(third);
    app.alive.delete("100:1"); app.close(third);
    const relaunched = window(101, "budget.ods — Editor");
    app.add(relaunched); app.settle(); placed(relaunched);
}
// A chooser can turn into a document in the same native window.
{
    const app = setup();
    const editor = window(200, "Templates — Editor");
    app.add(editor); app.settle(); unchanged(editor);
    editor.caption = "Untitled 1 — Editor";
    app.settle(); placed(editor);
}
// Existing windows at script startup and newly saved mappings remain untouched.
{
    const old = window(300, "existing.txt — Editor");
    const app = setup({ existing: [old] });
    app.settle(); unchanged(old);
    const another = window(300, "another.txt — Editor");
    app.add(another); app.settle(); unchanged(another);
    app.config({ titleIncludes: "another" }); app.settle(); unchanged(another);
}
// Startup grace treats newly restored windows as a baseline, too.
{
    const app = setup({ arm: false });
    const doc = window(350, "restored.txt — Editor");
    app.add(doc); app.settle();
    unchanged(doc); app.tick(31000); app.settle(); unchanged(doc);
}
// Missing destination or removed custom layout is skipped for the whole launch.
for (const change of [{ monitor: "UNPLUGGED" }, { layoutId: "custom:removed" }]) {
    const app = setup(); app.config(change);
    const doc = window(400, "doc.txt — Editor");
    app.add(doc); app.settle(); unchanged(doc);
    app.outputs.push({ name: "UNPLUGGED" }); app.settle(); unchanged(doc);
}
// A required title fragment overrides the generic document heuristic.
{
    const app = setup(); app.config({ titleIncludes: "Final document" });
    const doc = window(500, "Untitled — Editor");
    app.add(doc); app.settle(); unchanged(doc);
    doc.caption = "Final document — Editor"; app.settle(); placed(doc);
}
// First-eligible mode supports applications without document-like titles.
{
    const app = setup(); app.config({ windowRequirement: "firstEligibleWindow" });
    const doc = window(600, "Editor", { desktopFileName: "", resourceClass: "Editor" });
    app.add(doc); app.settle(); placed(doc);
}
// Geometry/readiness changes restart the settling delay; a user's drag is left alone.
{
    const app = setup();
    const doc = window(700, "doc.txt — Editor", { readyForPainting: false });
    app.add(doc); app.settle(); unchanged(doc);
    doc.readyForPainting = true; doc.interactiveMove = true;
    app.settle(); unchanged(doc);
    doc.interactiveMove = false; app.tick(100); unchanged(doc);
    app.tick(500); unchanged(doc); app.tick(600); placed(doc);
}
// Stable custom IDs survive reordering, and explicit output geometry respects panels.
{
    const app = setup({ custom: [
        { id: "first", name: "Other", x: 0, y: 0, width: .5, height: 1 },
        { id: "chosen", name: "Chosen", x: 0, y: 0, width: 1, height: .5 },
    ] });
    app.config({ layoutId: "custom:chosen" });
    const doc = window(800, "doc.txt — Editor"); app.add(doc); app.settle();
    assert.deepEqual({ ...doc.frameGeometry }, { x: 1920, y: 30, width: 1600, height: 425 });
}
// Concurrent window events must inspect process state in order, once per app.
{
    const app = setup({ asyncDBus: true });
    const doc = window(900, "doc.txt — Editor");
    const extra = window(900, "extra.txt — Editor");
    app.add(doc); app.add(extra);
    assert.equal(app.requests.length, 1);
    app.requests.shift()(); assert.equal(app.requests.length, 1);
    app.requests.shift()(); app.settle(); placed(doc); unchanged(extra);
}
process.stdout.write("KWin application launch mapping tests passed\n");
