#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""GTK editor acceptance checks; run in an isolated graphical test session."""
from pathlib import Path
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "helpers"))
from application_mappings import create_mapping_dialog

saved, errors = [], []


def children(widget):
    yield widget
    if isinstance(widget, Gtk.Container):
        for child in widget.get_children():
            yield from children(child)


def button(dialog, label):
    return next(widget for widget in children(dialog)
                if isinstance(widget, Gtk.Button) and widget.get_label() == label)


dialog = create_mapping_dialog(None, lambda: [], lambda rows: saved.append(rows), lambda: [
    {"id": "stable-custom", "name": "Custom editor", "x": 0, "y": 0, "width": .5, "height": 1},
])


def fill_editor():
    try:
        editor = next(window for window in Gtk.Window.list_toplevels() if window.get_title() == "Launch Mapping")
        grid = next(widget for widget in children(editor) if isinstance(widget, Gtk.Grid))
        application = grid.get_child_at(1, 0)
        assert application.get_model().iter_n_children(None) > 0, "Installed applications were not discovered"
        application.get_child().set_text("org.example.Editor")
        grid.get_child_at(1, 1).set_active_id("custom:stable-custom")
        grid.get_child_at(1, 2).get_child().set_text("DP-1")
        grid.get_child_at(1, 3).set_active_id("documentWindow")
        grid.get_child_at(1, 4).set_text("Editor document")
        grid.get_child_at(1, 5).set_text("Welcome; Templates")
        editor.response(Gtk.ResponseType.OK)
    except BaseException as error:
        errors.append(error)
        for window in Gtk.Window.list_toplevels():
            if window.get_title() == "Launch Mapping":
                window.response(Gtk.ResponseType.CANCEL)
    return False


def test():
    try:
        GLib.timeout_add(200, fill_editor)
        button(dialog, "Add…").emit("clicked")
        assert not saved, "Adding a draft mapping saved it prematurely"
        dialog.response(Gtk.ResponseType.OK)
        assert len(saved) == 1 and len(saved[0]) == 1
        row = saved[0][0]
        assert row["applicationId"] == "org.example.Editor"
        assert row["layoutId"] == "custom:stable-custom"
        assert row["monitor"] == "DP-1" and row["windowRequirement"] == "documentWindow"
        assert row["titleIncludes"] == "Editor document"
        assert row["excludedTitles"] == ["Welcome", "Templates"]
        second = create_mapping_dialog(None, lambda: saved[0], lambda rows: saved.append(rows), lambda: [])
        tree = next(widget for widget in children(second) if isinstance(widget, Gtk.TreeView))
        tree.get_selection().select_path(Gtk.TreePath.new_from_indices([0]))
        button(second, "Remove").emit("clicked")
        assert len(tree.get_model()) == 0
        second.response(Gtk.ResponseType.CANCEL)
        assert len(saved) == 1 and len(saved[0]) == 1, "Cancel committed a removal"
    except BaseException as error:
        errors.append(error)
    finally:
        Gtk.main_quit()
    return False


GLib.idle_add(test)
Gtk.main()
if errors:
    raise errors[0]
print("GTK mapping editor add, save, remove, cancel, and app-discovery checks passed")
