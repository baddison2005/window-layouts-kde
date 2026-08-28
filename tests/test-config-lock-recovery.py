#!/usr/bin/python3

# SPDX-License-Identifier: GPL-3.0-or-later

"""Regression checks for conservative KConfig lock recovery."""

import importlib.machinery
import importlib.util
import os
from pathlib import Path
import sys
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "cairo-dock-applet" / "window-layouts"))
sys.path.insert(0, str(PROJECT_ROOT / "helpers"))

loader = importlib.machinery.SourceFileLoader(
    "window_layouts_configurator_service",
    str(PROJECT_ROOT / "helpers" / "window-layouts-configurator-service"),
)
spec = importlib.util.spec_from_loader(loader.name, loader)
service = importlib.util.module_from_spec(spec)
loader.exec_module(service)


with tempfile.TemporaryDirectory() as temporary_directory:
    config_path = Path(temporary_directory) / "kwinrc"
    lock_path = config_path.with_name("kwinrc.lock")
    arguments = ["kwriteconfig6", "--file", str(config_path)]

    lock_path.write_text("999999999\nkwriteconfig6\n", encoding="utf-8")
    assert service.LayoutStorage._clear_abandoned_kconfig_lock(arguments)
    assert not lock_path.exists()

    lock_path.write_text(f"{os.getpid()}\nkwriteconfig6\n", encoding="utf-8")
    assert not service.LayoutStorage._clear_abandoned_kconfig_lock(arguments)
    assert lock_path.exists()

portable_id = "5cf56b58-e8c4-4b76-badc-9040f0457817"
validated_layout = service.LayoutStorage._validated_layout({
    "id": portable_id,
    "name": "Portable",
    "x": 0,
    "y": 0,
    "width": 0.5,
    "height": 1,
    "shortcutSlot": 3,
    "groupId": "",
}, 0)
assert validated_layout["id"] == portable_id

print("KConfig lock recovery checks passed")
