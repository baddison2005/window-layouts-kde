/*
 * SPDX-FileCopyrightText: 2026 Window Layouts contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Custom Layouts")
        icon: Qt.resolvedUrl("../images/window-layouts.svg")
        source: "config/ConfigLayouts.qml"
    }

    ConfigCategory {
        name: i18n("Layout Shortcuts")
        icon: "preferences-desktop-keyboard"
        source: "config/ConfigShortcuts.qml"
    }

    ConfigCategory {
        // Plasma owns the final native About page and does not expose an API
        // for third-party controls inside it. Keep update actions adjacent to
        // that page while metadata supplies the native About information.
        name: i18n("Updates")
        icon: "software-update-available"
        source: "config/ConfigUpdates.qml"
    }
}
