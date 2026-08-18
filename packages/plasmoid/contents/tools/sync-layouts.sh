#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

encoded_layouts=${1-}
encoded_groups=${2-}
printf -v layouts_json '%b' "${encoded_layouts//%/\\x}"
printf -v groups_json '%b' "${encoded_groups//%/\\x}"

# Refuse partial or malformed KCM state. In particular, an empty cfg_* value
# during Plasma startup must never replace valid shared configuration. A real
# request to remove every layout is represented by the valid JSON array `[]`.
validate_json_array() {
    python3 -c '
import json
import sys

value = json.loads(sys.argv[1])
if not isinstance(value, list):
    raise SystemExit("expected a JSON array")
print(json.dumps(value, separators=(",", ":"), ensure_ascii=False))
' "$1"
}

if ! layouts_json=$(validate_json_array "$layouts_json"); then
    printf '%s\n' "Window Layouts: refusing invalid custom-layout data" >&2
    exit 2
fi
if ! groups_json=$(validate_json_array "$groups_json"); then
    printf '%s\n' "Window Layouts: refusing invalid custom-group data" >&2
    exit 2
fi

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key CustomLayouts \
    "$layouts_json"

for group in \
    Script-windowlayouts \
    Script-windowlayoutsfloatingbutton \
    Script-windowlayoutsdragtargets
do
    kwriteconfig6 \
        --file kwinrc \
        --group "$group" \
        --key CustomGroups \
        "$groups_json"
done

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsfloatingbutton \
    --key CustomLayouts \
    "$layouts_json"

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key CustomLayouts \
    "$layouts_json"

if command -v qdbus-qt6 >/dev/null 2>&1; then
    qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null
    qdbus-qt6 \
        org.example.WindowLayouts.Configurator \
        /org/example/WindowLayouts/Configurator \
        org.example.WindowLayouts.Configurator.ClearUnusedCustomShortcuts \
        >/dev/null || true
    # Cairo-Dock's external applet does not receive Plasma configuration
    # notifications. Ask an already-running instance to rebuild its sub-dock
    # immediately; its periodic signature check remains the fallback.
    qdbus-qt6 \
        org.cairodock.CairoDock \
        /org/cairodock/CairoDock \
        org.cairodock.CairoDock.Reload \
        "module=window_layouts" \
        >/dev/null 2>&1 || true
fi
