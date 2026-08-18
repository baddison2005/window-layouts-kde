#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

floating_enabled=${1-false}
drag_targets_enabled=${2-false}
target_placement=${3-zones}
show_all_zone_targets=${4-false}
show_all_top_targets=${5-false}
floating_button_size=${6-default}
encoded_group_order=${7-%5B%22halves%22%2C%22quarters%22%2C%22thirds%22%2C%22twoThirds%22%2C%22custom%22%2C%22window%22%5D}
layout_padding=${8-0}
printf -v group_order '%b' "${encoded_group_order//%/\\x}"

case "$floating_enabled" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$drag_targets_enabled" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$target_placement" in
    zones|top) ;;
    *) exit 2 ;;
esac
case "$show_all_zone_targets" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$show_all_top_targets" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$floating_button_size" in
    small|default|big|extraBig) ;;
    *) exit 2 ;;
esac
case "$layout_padding" in
    ''|*[!0-9]*) exit 2 ;;
esac
if [ "$layout_padding" -gt 200 ]; then
    exit 2
fi

qdbus-qt6 \
    org.example.WindowLayouts.Configurator \
    /org/example/WindowLayouts/Configurator \
    org.example.WindowLayouts.Configurator.SetFeatureSettingsV3 \
    "$floating_enabled" \
    "$drag_targets_enabled" \
    "$target_placement" \
    "$show_all_zone_targets" \
    "$show_all_top_targets" \
    "$floating_button_size" \
    "$group_order" \
    "$layout_padding"
