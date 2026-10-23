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
const monitorIdentity = { manufacturer: "LG Electronics", model: "LG ULTRAGEAR+", serial: "LG-123" };
function setup({ existing = [], custom = [], asyncDBus = false, arm = true, mappings = null } = {}) {
    let now = 0;
    let rules = mappings || [{ applicationId: "org.example.Editor", applicationName: "Editor", wmClass: "Editor",
        layoutId: "WindowLayoutsRightHalf", monitor: "DP-2", monitorIdentity, windowRequirement: "documentWindow",
        titleIncludes: "", excludedTitles: ["Getting Started"] }];
    const outputs = [{ name: "DP-1", manufacturer: "Other", model: "Screen", serialNumber: "Other-123" },
        { name: "DP-2", manufacturer: monitorIdentity.manufacturer, model: monitorIdentity.model, serialNumber: monitorIdentity.serial }];
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
    function config(patch, notify = true) {
        rules = [{ ...rules[0], ...patch }];
        if (notify) context.options.configChanged.emit();
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
for (const change of [{ monitorIdentity: { ...monitorIdentity, serial: "UNPLUGGED" } }, { layoutId: "custom:removed" }]) {
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
// Opera GX reports a nonempty synthesized app ID that differs from its desktop
// file, but its exact StartupWMClass must still match the saved rule.
{
    const app = setup();
    app.config({ applicationId: "opera-gx", applicationName: "Opera GX", wmClass: "Opera GX",
        windowRequirement: "firstEligibleWindow" });
    const browser = window(1000, "GX Corner - Opera", { desktopFileName: "Opera GX", resourceClass: "Opera GX" });
    app.add(browser); app.settle(); placed(browser);
}
// A Steam sign-in window must not consume the rule before its resizable main window.
{
    const app = setup();
    app.config({ applicationId: "com.valvesoftware.Steam", applicationName: "Steam", wmClass: "Steam",
        windowRequirement: "firstEligibleWindow" });
    const login = window(1001, "Sign in to Steam", { desktopFileName: "", resourceClass: "steam", resizeable: false });
    app.add(login); app.settle(); unchanged(login); app.close(login);
    const main = window(1001, "Steam", { desktopFileName: "", resourceClass: "steam" });
    app.add(main); app.settle(); placed(main);
}
// Exact desktop IDs take precedence; ambiguous class aliases do not move a window.
{
    const base = { applicationName: "Editor", wmClass: "SharedEditor", monitor: "DP-2", monitorIdentity,
        windowRequirement: "firstEligibleWindow", titleIncludes: "", excludedTitles: [] };
    const app = setup({ mappings: [
        { ...base, applicationId: "one", layoutId: "WindowLayoutsLeftHalf" },
        { ...base, applicationId: "two", layoutId: "WindowLayoutsRightHalf" },
    ] });
    const exact = window(1002, "Editor", { desktopFileName: "two", resourceClass: "SharedEditor" });
    app.add(exact); app.settle(); placed(exact);
    const ambiguous = window(1003, "Editor", { desktopFileName: "unknown", resourceClass: "SharedEditor" });
    app.add(ambiguous); app.settle(); unchanged(ambiguous);
}
// Flatpak gedit has no StartupWMClass and exposes only its short application ID.
{
    const base = { applicationName: "gedit", wmClass: "", monitor: "DP-2", monitorIdentity,
        layoutId: "WindowLayoutsRightHalf", windowRequirement: "firstEligibleWindow",
        titleIncludes: "", excludedTitles: [] };
    const rule = { ...base, applicationId: "org.gnome.gedit" };
    const app = setup({ mappings: [rule] });
    const editor = window(1010, "Untitled Document 1", { desktopFileName: "gedit", resourceClass: "gedit" });
    app.add(editor); app.settle(); placed(editor);
    const ambiguous = setup({ mappings: [rule, { ...base, applicationId: "org.other.gedit" }] });
    const shared = window(1011, "Untitled", { desktopFileName: "gedit", resourceClass: "gedit" });
    ambiguous.add(shared); ambiguous.settle(); unchanged(shared);
    const exact = setup({ mappings: [rule, { ...base, applicationId: "gedit", layoutId: "WindowLayoutsLeftHalf" }] });
    const preferred = window(1012, "Untitled", { desktopFileName: "gedit", resourceClass: "gedit" });
    exact.add(preferred); exact.settle();
    assert.equal(preferred.frameGeometry.x, 1920);
    const explicit = setup({ mappings: [{ ...rule, wmClass: "OtherEditor" }] });
    const mismatch = window(1013, "Untitled", { desktopFileName: "gedit", resourceClass: "gedit" });
    explicit.add(mismatch); explicit.settle(); unchanged(mismatch);
}
// Activation may precede windowAdded; a subsequently announced identity still
// belongs to this new launch rather than the existing-window baseline.
{
    const app = setup();
    const late = window(1004, "doc.txt", { desktopFileName: "", resourceClass: "", desktopFileNameChanged: signal() });
    app.workspace.windowActivated.emit(late);
    app.add(late);
    late.desktopFileName = "org.example.Editor";
    late.desktopFileNameChanged.emit();
    app.settle(); placed(late);
}
// Saving script-only settings need not emit KWin's generic options signal.
// The next added window picks up the rule without baselining itself away.
{
    const app = setup({ mappings: [] });
    app.config({ applicationId: "org.example.Editor", applicationName: "Editor", wmClass: "Editor",
        layoutId: "WindowLayoutsRightHalf", monitor: "DP-2", monitorIdentity, windowRequirement: "firstEligibleWindow",
        titleIncludes: "", excludedTitles: [] }, false);
    const fresh = window(1005, "Editor");
    app.add(fresh); app.settle(); placed(fresh);
}
// The LG follows port changes even when another monitor occupies its old port.
{
    const app = setup();
    app.outputs[0].name = "DP-2";
    app.outputs[1].name = "HDMI-A-1";
    const doc = window(1100, "doc.txt");
    app.add(doc); app.settle(); placed(doc);
    assert.equal(doc.output, app.outputs[1]);
}
// Missing, ambiguous, and legacy identities never fall back to the old connector.
for (const kind of ["missing", "duplicate", "legacy", "malformed"]) {
    const app = setup();
    if (kind === "missing") app.outputs[1].serialNumber = "Different-monitor";
    if (kind === "duplicate") app.outputs.push({ ...app.outputs[1], name: "HDMI-A-1" });
    if (kind === "legacy") app.config({ monitorIdentity: undefined });
    if (kind === "malformed") app.config({ monitorIdentity: { serial: "LG-123" } });
    const doc = window(1101, "doc.txt");
    app.add(doc); app.settle(); unchanged(doc);
}
// No serial: require both model and connector, and never guess across ports.
for (const serial of ["", "0", "unknown", "none", "n/a"]) {
    const app = setup();
    app.config({ monitorIdentity: { ...monitorIdentity, serial } });
    app.outputs[1].serialNumber = serial;
    const doc = window(1102, "doc.txt");
    app.add(doc); app.settle(); placed(doc);
    app.close(doc); app.alive.delete("1102:1");
    app.outputs[1].name = "HDMI-A-1";
    const next = window(1103, "next.txt");
    app.add(next); app.settle(); unchanged(next);
}
process.stdout.write("KWin application launch mapping tests passed\n");
