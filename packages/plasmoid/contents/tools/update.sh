#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Dr. Bret Addison
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

case "${1:-}" in
    check|install)
        action=$1
        ;;
    *)
        printf '%s\n' '{"error":"Usage: update.sh check|install"}'
        exit 2
        ;;
esac

data_directory=$(qtpaths6 --writable-path GenericDataLocation)
updater="$data_directory/window-layouts-kde/configurator/updater.py"
if [ ! -f "$updater" ]; then
    printf '%s\n' '{"error":"The Window Layouts update service is not installed"}'
    exit 0
fi
exec python3 "$updater" "$action"
