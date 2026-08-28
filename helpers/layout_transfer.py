#!/usr/bin/python3

# SPDX-FileCopyrightText: 2026 Dr. Bret Addison
# SPDX-License-Identifier: GPL-3.0-or-later

"""Portable JSON import/export for custom Window Layouts and groups."""

import argparse
import json
import math
import os
from pathlib import Path
import tempfile
import urllib.parse
import uuid


SCHEMA_VERSION = 1
MAX_LAYOUTS = 20
MAX_GROUPS = 20
MAX_NAME_LENGTH = 80
MAX_ARCHIVE_BYTES = 1024 * 1024


class LayoutTransferError(ValueError):
    """Raised when a layout archive is unsafe or incompatible."""


def _name(value, label):
    if not isinstance(value, str) or not value.strip():
        raise LayoutTransferError(f"Every {label} must have a name")
    result = value.strip()
    if len(result) > MAX_NAME_LENGTH:
        raise LayoutTransferError(
            f"A {label} name cannot exceed {MAX_NAME_LENGTH} characters"
        )
    return result


def _uuid(value, label, generate_missing=False):
    if generate_missing and (not isinstance(value, str) or not value):
        return str(uuid.uuid4())
    try:
        return str(uuid.UUID(value))
    except (AttributeError, TypeError, ValueError) as error:
        raise LayoutTransferError(f"Every {label} must have a valid UUID") from error


def _portable_uuid(value):
    """Keep a UUID when present or map a legacy KDE identifier to a new UUID."""
    try:
        return str(uuid.UUID(value))
    except (AttributeError, TypeError, ValueError):
        return str(uuid.uuid4())


def _number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise LayoutTransferError(f"Layout {label} must be a number")
    result = float(value)
    if not math.isfinite(result):
        raise LayoutTransferError(f"Layout {label} must be finite")
    return result


def _geometry(candidate):
    x = _number(candidate.get("x"), "x")
    y = _number(candidate.get("y"), "y")
    width = _number(candidate.get("width"), "width")
    height = _number(candidate.get("height"), "height")
    if (x < 0 or y < 0 or width <= 0 or height <= 0
            or x + width > 1.000001 or y + height > 1.000001):
        raise LayoutTransferError(
            "Every layout must fit within normalized display coordinates"
        )
    return x, y, width, height


def _optional_slots(items, key, label):
    """Preserve valid KDE slots and allocate missing macOS slots by order."""
    used = set()
    result = []
    for item in items:
        value = item.get(key)
        if value is None:
            value = next(
                (slot for slot in range(1, MAX_LAYOUTS + 1) if slot not in used),
                None,
            )
        if (isinstance(value, bool) or not isinstance(value, int)
                or not 1 <= value <= MAX_LAYOUTS or value in used):
            raise LayoutTransferError(f"{label} shortcut slots must be unique from 1 to 20")
        used.add(value)
        result.append(value)
    return result


def build_archive(custom_layouts, custom_groups):
    """Create a macOS-compatible archive from the current KDE draft."""
    if not isinstance(custom_layouts, list) or not isinstance(custom_groups, list):
        raise LayoutTransferError("Custom layouts and groups must be arrays")
    if len(custom_layouts) > MAX_LAYOUTS:
        raise LayoutTransferError("An archive may contain no more than 20 custom layouts")
    if len(custom_groups) > MAX_GROUPS:
        raise LayoutTransferError("An archive may contain no more than 20 custom groups")

    group_slots = _optional_slots(custom_groups, "fillShortcutSlot", "Custom group")
    source_group_ids = set()
    group_id_map = {}
    portable_groups = []
    portable_group_ids = set()
    for index, group in enumerate(custom_groups):
        if not isinstance(group, dict):
            raise LayoutTransferError("Every custom group must be an object")
        source_id = group.get("id")
        if not isinstance(source_id, str) or not source_id or source_id in source_group_ids:
            raise LayoutTransferError("Custom group identifiers must be non-empty and unique")
        source_group_ids.add(source_id)
        portable_id = _portable_uuid(source_id)
        while portable_id in portable_group_ids:
            portable_id = str(uuid.uuid4())
        portable_group_ids.add(portable_id)
        group_id_map[source_id] = portable_id
        portable_groups.append({
            "id": portable_id,
            "name": _name(group.get("name"), "custom group"),
            "fillShortcutSlot": group_slots[index],
        })

    layout_slots = _optional_slots(custom_layouts, "shortcutSlot", "Custom layout")
    portable_layouts = []
    portable_layout_ids = set()
    for index, layout in enumerate(custom_layouts):
        if not isinstance(layout, dict):
            raise LayoutTransferError("Every custom layout must be an object")
        layout_id = _portable_uuid(layout.get("id"))
        if layout_id in portable_layout_ids:
            raise LayoutTransferError("Custom layout identifiers must be unique")
        portable_layout_ids.add(layout_id)
        x, y, width, height = _geometry(layout)
        portable = {
            "id": layout_id,
            "name": _name(layout.get("name"), "custom layout"),
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "shortcutSlot": layout_slots[index],
        }
        source_group_id = layout.get("groupId")
        if source_group_id:
            if source_group_id not in group_id_map:
                raise LayoutTransferError("A custom layout refers to a group that does not exist")
            portable["groupId"] = group_id_map[source_group_id]
        portable_layouts.append(portable)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "customLayouts": portable_layouts,
        "customGroups": portable_groups,
    }


def validate_archive(archive):
    """Validate a portable archive and return normalized KDE records."""
    if not isinstance(archive, dict):
        raise LayoutTransferError("The archive must contain a JSON object")
    if archive.get("schemaVersion") != SCHEMA_VERSION:
        raise LayoutTransferError("The layout archive uses an unsupported schema version")
    layouts = archive.get("customLayouts")
    groups = archive.get("customGroups")
    if not isinstance(layouts, list) or not isinstance(groups, list):
        raise LayoutTransferError("The archive must contain customLayouts and customGroups arrays")
    if len(layouts) > MAX_LAYOUTS:
        raise LayoutTransferError("An archive may contain no more than 20 custom layouts")
    if len(groups) > MAX_GROUPS:
        raise LayoutTransferError("An archive may contain no more than 20 custom groups")

    group_slots = _optional_slots(groups, "fillShortcutSlot", "Custom group")
    normalized_groups = []
    group_ids = set()
    for index, group in enumerate(groups):
        if not isinstance(group, dict):
            raise LayoutTransferError("Every custom group must be an object")
        group_id = _uuid(group.get("id"), "custom group")
        if group_id in group_ids:
            raise LayoutTransferError("Custom group identifiers must be unique")
        group_ids.add(group_id)
        normalized_groups.append({
            "id": group_id,
            "name": _name(group.get("name"), "custom group"),
            "fillShortcutSlot": group_slots[index],
        })

    layout_slots = _optional_slots(layouts, "shortcutSlot", "Custom layout")
    normalized_layouts = []
    layout_ids = set()
    for index, layout in enumerate(layouts):
        if not isinstance(layout, dict):
            raise LayoutTransferError("Every custom layout must be an object")
        layout_id = _uuid(layout.get("id"), "custom layout")
        if layout_id in layout_ids:
            raise LayoutTransferError("Custom layout identifiers must be unique")
        layout_ids.add(layout_id)
        x, y, width, height = _geometry(layout)
        group_id = layout.get("groupId")
        if group_id in (None, ""):
            group_id = ""
        else:
            group_id = _uuid(group_id, "custom group reference")
            if group_id not in group_ids:
                raise LayoutTransferError("A custom layout refers to a group that does not exist")
        normalized_layouts.append({
            "id": layout_id,
            "name": _name(layout.get("name"), "custom layout"),
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "shortcutSlot": layout_slots[index],
            "groupId": group_id,
        })

    return {
        "customLayouts": normalized_layouts,
        "customGroups": normalized_groups,
    }


def export_archive(path, custom_layouts, custom_groups):
    """Atomically write an archive to a user-selected path."""
    destination = Path(path)
    if not destination.parent.is_dir():
        raise LayoutTransferError("The selected destination folder does not exist")
    archive = build_archive(custom_layouts, custom_groups)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            json.dump(
                archive,
                temporary,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, destination)
    except OSError as error:
        raise LayoutTransferError(f"Could not export the layout archive: {error}") from error
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
    return archive


def import_archive(path):
    """Read and validate a user-selected archive."""
    source = Path(path)
    try:
        if source.stat().st_size > MAX_ARCHIVE_BYTES:
            raise LayoutTransferError("The selected layout archive is too large")
        archive = json.loads(source.read_text(encoding="utf-8"))
    except LayoutTransferError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise LayoutTransferError(f"Could not read the layout archive: {error}") from error
    return validate_archive(archive)


def _cli():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    import_parser = subparsers.add_parser("import")
    import_parser.add_argument("path")
    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("path")
    export_parser.add_argument("layouts")
    export_parser.add_argument("groups")
    arguments = parser.parse_args()

    try:
        if arguments.action == "import":
            result = import_archive(arguments.path)
        else:
            layouts = json.loads(urllib.parse.unquote(arguments.layouts))
            groups = json.loads(urllib.parse.unquote(arguments.groups))
            archive = export_archive(arguments.path, layouts, groups)
            result = {
                "exported": True,
                "layoutCount": len(archive["customLayouts"]),
                "groupCount": len(archive["customGroups"]),
            }
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
        return 0
    except (LayoutTransferError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
