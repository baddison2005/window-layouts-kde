#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

operation=${1-get}
if [ "$operation" = get ]; then
    qdbus-qt6 \
        org.example.WindowLayouts.Configurator \
        /org/example/WindowLayouts/Configurator \
        org.example.WindowLayouts.Configurator.GetShortcutsJson
    exit
fi

encoded_action=${2-}
encoded_shortcut=${3-}
printf -v action_id '%b' "${encoded_action//%/\\x}"
printf -v shortcut_text '%b' "${encoded_shortcut//%/\\x}"
qdbus-qt6 \
    org.example.WindowLayouts.Configurator \
    /org/example/WindowLayouts/Configurator \
    org.example.WindowLayouts.Configurator.SetShortcutText \
    "$action_id" \
    "$shortcut_text" \
    true
