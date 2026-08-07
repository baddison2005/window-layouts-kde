/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

const widgetType = "org.example.windowlayouts";
const availablePanels = panels();

if (!knownWidgetTypes.includes(widgetType)) {
    throw new Error("The Window Layouts Plasmoid is not installed");
}

if (availablePanels.length === 0) {
    throw new Error("No Plasma panel is available");
}

function widgetsIn(containment) {
    return containment.widgetIds.map(id => containment.widgetById(id));
}

let panelInstance = null;

for (const panel of availablePanels) {
    for (const widget of widgetsIn(panel)) {
        if (widget && widget.type === widgetType) {
            panelInstance = widget;
            break;
        }
    }

    if (panelInstance) {
        break;
    }
}

if (!panelInstance) {
    // Prefer the primary screen's panel; otherwise use the first panel.
    const targetPanel = availablePanels.find(panel => panel.screen === 0)
        || availablePanels[0];
    panelInstance = targetPanel.addWidget(widgetType);
    print(`Added Window Layouts to panel ${targetPanel.id}`);
} else {
    print("Window Layouts is already present on a panel");
}

let removedDesktopInstances = 0;

for (const desktop of desktops()) {
    for (const widget of widgetsIn(desktop)) {
        if (widget && widget.type === widgetType) {
            widget.remove();
            removedDesktopInstances += 1;
        }
    }
}

print(`Removed ${removedDesktopInstances} desktop instance(s)`);
