#!/usr/bin/python3

# SPDX-License-Identifier: GPL-3.0-or-later

"""Keep release and About metadata synchronized across every frontend."""

import json
from pathlib import Path
import re


PROJECT_ROOT = Path(__file__).resolve().parent.parent
version = (PROJECT_ROOT / "VERSION").read_text(encoding="utf-8").strip()
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)

for metadata_path in sorted((PROJECT_ROOT / "packages").glob("*/metadata.json")):
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))["KPlugin"]
    assert metadata["Version"] == version, metadata_path
    assert metadata["Authors"][0]["Name"] == "Dr. Bret Addison", metadata_path
    assert metadata["Website"] == (
        "https://github.com/baddison2005/window-layouts-kde"
    ), metadata_path
    assert metadata["BugReportUrl"] == (
        "https://github.com/baddison2005/window-layouts-kde/issues"
    ), metadata_path

updater_source = (PROJECT_ROOT / "helpers" / "updater.py").read_text(
    encoding="utf-8"
)
gtk_source = (
    PROJECT_ROOT / "cairo-dock-applet" / "window-layouts" / "configurator.py"
).read_text(encoding="utf-8")
updates_qml = (
    PROJECT_ROOT
    / "packages"
    / "plasmoid"
    / "contents"
    / "ui"
    / "config"
    / "ConfigUpdates.qml"
).read_text(encoding="utf-8")
for source in (updater_source, gtk_source, updates_qml):
    assert f'"{version}"' in source

auto_load = (
    PROJECT_ROOT / "cairo-dock-applet" / "window-layouts" / "auto-load.conf"
).read_text(encoding="utf-8")
assert f"version = {version}" in auto_load
assert "author = Dr. Bret Addison" in auto_load

upgrade_installer = (PROJECT_ROOT / "install-drag-overlay.sh").read_text(
    encoding="utf-8"
)
clean_installer = (PROJECT_ROOT / "install.sh").read_text(encoding="utf-8")
assert 'application_version=$(sed -n \'1p\' "$version_source")' in upgrade_installer
assert 'runtime_version="$application_version-$runtime_cachebuster"' in upgrade_installer
assert "previous_plasmoid_version" in upgrade_installer
for installer in (upgrade_installer, clean_installer):
    assert "plasma-plasmashell.service" in installer
    assert "systemd-run" in installer
    assert "previous_plasmoid_version" in installer

print("Release metadata checks passed")
