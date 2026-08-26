#!/usr/bin/env node

/* SPDX-License-Identifier: GPL-2.0-or-later */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(
    __dirname,
    "..",
    "packages",
    "drag-overlay",
    "contents",
    "ui",
    "DragTargetController.qml",
), "utf8");

// These guards deliberately overlap. A regression must not leave an inactive,
// screen-sized Wayland surface on the desktop or add an unsupported input mask.
assert.match(source, /property PlasmaCore\.Dialog overlayWindow: PlasmaCore\.Dialog\s*\{/);
assert.match(source, /readonly property bool safelyMapped:\s*controller\.dragActive\s*&& controller\.overlayMapped/);
assert.match(source, /visible:\s*true/);
assert.match(source, /opacity:\s*safelyMapped \? 1 : 0/);
assert.match(source, /x:\s*safelyMapped \? controller\.availableArea\.x : -32768/);
assert.match(source, /y:\s*safelyMapped \? controller\.availableArea\.y : -32768/);
assert.match(source, /width:\s*safelyMapped \? controller\.availableArea\.width : 1/);
assert.match(source, /height:\s*safelyMapped \? controller\.availableArea\.height : 1/);
assert.match(source, /function finishOverlayRemap\(revision\)[\s\S]*?if \(!isInteractiveMove\(dragWindow\)\)\s*\{\s*finishDrag\(false\)/);
assert.doesNotMatch(source, /outputOnly:\s*true/);
assert.doesNotMatch(source, /property Loader overlayLoader/);

process.stdout.write("Drag-overlay fail-safe checks passed\n");
