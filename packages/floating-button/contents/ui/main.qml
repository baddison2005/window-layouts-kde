/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.kwin
import "components" as Components

QtObject {
    id: controller

    property Components.FloatingButton button: Components.FloatingButton {}

    property Timer focusTimer: Timer {
        // Signal delivery can be temporarily disrupted while KWin changes
        // focus or runs an interactive move/resize. This lightweight poll is
        // the authoritative liveness check and repairs missed transitions.
        interval: 250
        repeat: true
        running: true
        onTriggered: controller.button.syncActiveWindow()
    }

    property Connections workspaceConnections: Connections {
        target: Workspace
        ignoreUnknownSignals: true

        function onWindowActivated(_window) {
            controller.button.syncActiveWindow();
        }

        function onWindowAdded(_window) {
            Qt.callLater(controller.button.syncActiveWindow);
        }

        function onWindowRemoved(_window) {
            Qt.callLater(controller.button.syncActiveWindow);
        }
    }
}
