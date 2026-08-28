#!/usr/bin/python3

# SPDX-License-Identifier: GPL-3.0-or-later

"""Regression checks for the portable custom-layout archive."""

import json
from pathlib import Path
import sys
import tempfile
import uuid


PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "helpers"))

from layout_transfer import (  # noqa: E402
    LayoutTransferError,
    build_archive,
    export_archive,
    import_archive,
    validate_archive,
)


layouts = [{
    "name": "Bottom Left Third",
    "x": 0,
    "y": 1 / 3,
    "width": 1 / 3,
    "height": 2 / 3,
    "shortcutSlot": 4,
    "groupId": "legacy-bottom-thirds",
}]
groups = [{
    "id": "legacy-bottom-thirds",
    "name": "Bottom Thirds",
    "fillShortcutSlot": 7,
}]

archive = build_archive(layouts, groups)
assert archive["schemaVersion"] == 1
assert uuid.UUID(archive["customLayouts"][0]["id"])
assert uuid.UUID(archive["customGroups"][0]["id"])
assert archive["customLayouts"][0]["groupId"] == archive["customGroups"][0]["id"]
assert archive["customLayouts"][0]["shortcutSlot"] == 4
assert archive["customGroups"][0]["fillShortcutSlot"] == 7

with tempfile.TemporaryDirectory() as directory:
    destination = Path(directory) / "Window Layouts Custom Layouts.json"
    export_archive(destination, layouts, groups)
    decoded = json.loads(destination.read_text(encoding="utf-8"))
    assert decoded["schemaVersion"] == 1
    assert decoded["customLayouts"][0]["name"] == layouts[0]["name"]
    assert decoded["customGroups"][0]["name"] == groups[0]["name"]
    imported = import_archive(destination)
    assert imported["customLayouts"][0]["shortcutSlot"] == 4
    assert imported["customGroups"][0]["fillShortcutSlot"] == 7

mac_group_id = str(uuid.uuid4())
mac_layout_id = str(uuid.uuid4())
mac_archive = {
    "schemaVersion": 1,
    "customLayouts": [{
        "id": mac_layout_id,
        "name": "Writing",
        "x": 0.5,
        "y": 0,
        "width": 0.5,
        "height": 1,
        "groupId": mac_group_id,
    }],
    "customGroups": [{"id": mac_group_id, "name": "Focus"}],
}
normalized = validate_archive(mac_archive)
assert normalized["customLayouts"][0]["shortcutSlot"] == 1
assert normalized["customGroups"][0]["fillShortcutSlot"] == 1
assert normalized["customLayouts"][0]["id"] == mac_layout_id

bad_archives = [
    {**mac_archive, "schemaVersion": 99},
    {**mac_archive, "customLayouts": [
        {**mac_archive["customLayouts"][0], "width": 2},
    ]},
    {**mac_archive, "customLayouts": [
        {**mac_archive["customLayouts"][0], "groupId": str(uuid.uuid4())},
    ]},
    {**mac_archive, "customLayouts": [
        {**mac_archive["customLayouts"][0], "id": "not-a-uuid"},
    ]},
    {**mac_archive, "customLayouts": mac_archive["customLayouts"] * 21},
]
for candidate in bad_archives:
    try:
        validate_archive(candidate)
    except LayoutTransferError:
        pass
    else:
        raise AssertionError("Invalid archive was accepted")

panel_source = (
    PROJECT_ROOT / "packages/plasmoid/contents/ui/config/ConfigLayouts.qml"
).read_text(encoding="utf-8")
gtk_source = (
    PROJECT_ROOT / "cairo-dock-applet/window-layouts/configurator.py"
).read_text(encoding="utf-8")
assert 'text: i18n("Import…")' in panel_source
assert 'text: i18n("Export…")' in panel_source
assert "layout-transfer.sh" in panel_source
assert "Replace custom layouts and groups?" in panel_source
assert '"Import…", "document-import"' in gtk_source
assert '"Export…", "document-export"' in gtk_source
assert "Replace custom layouts and groups?" in gtk_source

print("Layout transfer checks passed")
