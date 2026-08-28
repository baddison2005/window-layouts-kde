#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Dr. Bret Addison
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

data_directory=$(qtpaths6 --writable-path GenericDataLocation)
transfer_helper="$data_directory/window-layouts-kde/configurator/layout_transfer.py"
if [ ! -f "$transfer_helper" ]; then
    printf '%s\n' '{"error":"The Window Layouts transfer service is not installed"}'
    exit 1
fi

exec python3 "$transfer_helper" "$@"
