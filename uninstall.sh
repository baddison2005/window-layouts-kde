#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

data_directory=$(qtpaths6 --writable-path GenericDataLocation)
configurator_directory="$data_directory/window-layouts-kde/configurator"
tools_directory="$data_directory/window-layouts-kde/tools"
configurator_service="$data_directory/dbus-1/services/org.example.WindowLayouts.Configurator.service"

if command -v qdbus-qt6 >/dev/null 2>&1; then
    qdbus-qt6 \
        org.example.WindowLayouts.Configurator \
        /org/example/WindowLayouts/Configurator \
        org.example.WindowLayouts.Configurator.Quit \
        >/dev/null 2>&1 || true
fi

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsEnabled \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsfloatingEnabled \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsfloatingbuttonEnabled \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsdragtargetsEnabled \
    --type bool \
    false

if command -v qdbus-qt6 >/dev/null 2>&1; then
    qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null || true
fi

if kpackagetool6 --type Plasma/Applet --show org.example.windowlayouts >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --remove org.example.windowlayouts
fi

if kpackagetool6 --type KWin/Script --show windowlayouts >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --remove windowlayouts
fi

if kpackagetool6 --type KWin/Script --show windowlayoutsfloatingbutton >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --remove windowlayoutsfloatingbutton
fi

if kpackagetool6 --type KWin/Script --show windowlayoutsdragtargets >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --remove windowlayoutsdragtargets
fi

# Remove the short-lived development ID used by the first drag-target build.
if kpackagetool6 --type KWin/Script --show windowlayoutsdragoverlay >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --remove windowlayoutsdragoverlay
fi

rm -f \
    "$configurator_directory/window-layouts-configurator-service" \
    "$configurator_directory/configurator.py" \
    "$configurator_directory/updater.py" \
    "$configurator_directory/layout_transfer.py" \
    "$configurator_directory/VERSION" \
    "$configurator_directory/window-layouts.svg" \
    "$configurator_service"
rmdir "$configurator_directory" 2>/dev/null || true
rm -f "$tools_directory/xwayland-video-bridge-workaround"
rmdir "$tools_directory" 2>/dev/null || true
rmdir "$data_directory/window-layouts-kde" 2>/dev/null || true

if command -v dbus-send >/dev/null 2>&1; then
    dbus-send \
        --session \
        --type=method_call \
        --dest=org.freedesktop.DBus \
        / \
        org.freedesktop.DBus.ReloadConfig
fi

printf '%s\n' "Window Layouts uninstalled."
