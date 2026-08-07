#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

floating_enabled=${1-false}
drag_targets_enabled=${2-false}
show_all_drag_targets=${3-false}
floating_button_size=${4-default}
encoded_group_order=${5-%5B%22halves%22%2C%22quarters%22%2C%22thirds%22%2C%22twoThirds%22%2C%22custom%22%2C%22window%22%5D}
printf -v group_order '%b' "${encoded_group_order//%/\\x}"

case "$floating_enabled" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$drag_targets_enabled" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$show_all_drag_targets" in
    true|false) ;;
    *) exit 2 ;;
esac
case "$floating_button_size" in
    small|default|big|extraBig) ;;
    *) exit 2 ;;
esac

qdbus-qt6 \
    org.example.WindowLayouts.Configurator \
    /org/example/WindowLayouts/Configurator \
    org.example.WindowLayouts.Configurator.SetFeatureSettings \
    "$floating_enabled" \
    "$drag_targets_enabled" \
    "$show_all_drag_targets" \
    "$floating_button_size" \
    "$group_order"
