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
}
