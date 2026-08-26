#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper="$project_directory/helpers/xwayland-video-bridge-workaround"
test_config_directory=$(mktemp -d)
trap 'rm -rf "$test_config_directory"' EXIT HUP INT TERM

run_helper() {
    WINDOW_LAYOUTS_XDG_CONFIG_HOME="$test_config_directory" \
        "$helper" "$@"
}

run_helper status | grep -Fq 'Autostart: enabled by the system desktop entry'
run_helper disable >/dev/null

override="$test_config_directory/autostart/org.kde.xwaylandvideobridge.desktop"
test -f "$override"
grep -Fqx 'Hidden=true' "$override"
grep -Fqx 'X-Window-Layouts-Managed=true' "$override"
run_helper status | grep -Fq 'Autostart: disabled by the Window Layouts workaround'

run_helper enable >/dev/null
test ! -e "$override"

install -d -m 755 "$(dirname -- "$override")"
printf '%s\n' '[Desktop Entry]' 'Hidden=true' > "$override"
if run_helper disable >/dev/null 2>&1; then
    printf '%s\n' 'Helper overwrote an unrelated user override' >&2
    exit 1
fi
grep -Fqx 'Hidden=true' "$override"
test "$(wc -l < "$override")" -eq 2

printf '%s\n' 'Xwayland Video Bridge workaround checks passed'
