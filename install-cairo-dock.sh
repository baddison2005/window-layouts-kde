#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_directory="$project_directory/cairo-dock-applet/window-layouts"
config_directory=$(qtpaths6 --writable-path ConfigLocation)
destination="$config_directory/cairo-dock/third-party/window_layouts"
data_directory=$(qtpaths6 --writable-path GenericDataLocation)
guard_directory="$data_directory/window-layouts-kde"
systemd_directory="$config_directory/systemd/user"
autostart_dropin="$systemd_directory/app-cairo\\x2ddock@autostart.service.d"

mkdir -p "$destination"
install -m 755 "$source_directory/window-layouts" "$destination/window_layouts"
install -m 644 "$source_directory/configurator.py" "$destination/configurator.py"
install -m 644 "$source_directory/auto-load.conf" "$destination/auto-load.conf"
install -m 644 "$source_directory/window-layouts.conf" "$destination/window_layouts.conf"
install -m 644 "$source_directory/icon" "$destination/icon"
install -m 644 "$source_directory/preview" "$destination/preview"

install -d -m 755 "$guard_directory" "$autostart_dropin" "$systemd_directory"
install -m 755 \
    "$project_directory/cairo-dock-applet/cairo-dock-unlock-guard" \
    "$guard_directory/cairo-dock-unlock-guard"
install -m 644 \
    "$project_directory/cairo-dock-applet/systemd/cairo-dock-autostart-restart.conf" \
    "$autostart_dropin/restart.conf"
install -m 644 \
    "$project_directory/cairo-dock-applet/systemd/cairo-dock-unlock-guard.service" \
    "$systemd_directory/cairo-dock-unlock-guard.service"

systemctl --user daemon-reload
systemctl --user enable cairo-dock-unlock-guard.service
systemctl --user restart cairo-dock-unlock-guard.service
"$guard_directory/cairo-dock-unlock-guard" --restore-now

printf '%s\n' \
    "Window Layouts for Cairo-Dock installed." \
    "Cairo-Dock will stay on KDE's primary output across screen changes and unlocks." \
    "Enable it from Cairo-Dock Configuration → Add-ons → Window Layouts."
