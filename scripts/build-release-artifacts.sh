#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Dr. Bret Addison
# SPDX-License-Identifier: GPL-3.0-or-later

# Build the versioned archive and checksum expected by the in-app updater.

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(sed -n '1p' "$project_directory/VERSION")
release_ref=${1:-HEAD}
output_directory=${2:-"$project_directory/dist"}
archive_name="window-layouts-kde-v$version.tar.gz"

case "$version" in
    ''|*[!0-9.]*)
        printf '%s\n' "VERSION must contain a semantic version" >&2
        exit 1
        ;;
esac

mkdir -p "$output_directory"
git -C "$project_directory" archive \
    --format=tar.gz \
    --prefix="window-layouts-kde-v$version/" \
    --output="$output_directory/$archive_name" \
    "$release_ref"

(
    cd "$output_directory"
    sha256sum "$archive_name" > "$archive_name.sha256"
)

printf '%s\n' \
    "$output_directory/$archive_name" \
    "$output_directory/$archive_name.sha256"
