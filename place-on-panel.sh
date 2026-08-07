#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script_path="$project_dir/scripts/place-on-panel.js"

if ! command -v qdbus-qt6 >/dev/null 2>&1; then
    printf '%s\n' "qdbus-qt6 is required to update the Plasma layout." >&2
    exit 1
fi

plasma_script=$(<"$script_path")
qdbus-qt6 \
    org.kde.plasmashell \
    /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript \
    "$plasma_script"

printf '%s\n' \
    "Window Layouts is now on a Plasma panel." \
    "Any Window Layouts instances on the desktop were removed."
