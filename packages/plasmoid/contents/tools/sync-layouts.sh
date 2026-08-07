#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

encoded_layouts=${1-}
printf -v layouts_json '%b' "${encoded_layouts//%/\\x}"

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key CustomLayouts \
    "$layouts_json"

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
fi
