#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""GTK editor acceptance checks; run in an isolated graphical test session."""
from pathlib import Path
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "helpers"))
from application_mappings import connected_monitors, create_mapping_dialog

saved, errors = [], []
monitors = connected_monitors()
assert monitors, "KWin monitor identities could not be queried"


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
        monitor = grid.get_child_at(1, 2)
        assert monitor.get_model().iter_n_children(None) > 0
        monitor.set_active(0)
        assert monitors[0]["identity"]["model"] or "Unnamed monitor" in monitor.get_active_text()
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
        assert row["monitor"] == monitors[0]["connector"] and row["windowRequirement"] == "documentWindow"
        assert row["monitorIdentity"] == monitors[0]["identity"]
        assert row["titleIncludes"] == "Editor document"
        assert row["excludedTitles"] == ["Welcome", "Templates"]
        missing = [{**row, "monitorIdentity": {**row["monitorIdentity"], "serial": "unplugged-test"}}]
        second = create_mapping_dialog(None, lambda: missing, lambda rows: saved.append(rows), lambda: [])
        tree = next(widget for widget in children(second) if isinstance(widget, Gtk.TreeView))
        # A physically missing monitor is flagged even if its old port still exists.
        assert "unavailable" in tree.get_model()[0][2]
        assert any(isinstance(widget, Gtk.Label) and "Mappings skipped until their monitor" in widget.get_text()
                   for widget in children(second))
        tree.get_selection().select_path(Gtk.TreePath.new_from_indices([0]))
        button(second, "Remove").emit("clicked")
        assert len(tree.get_model()) == 0
        second.response(Gtk.ResponseType.CANCEL)
        assert len(saved) == 1 and len(saved[0]) == 1, "Cancel committed a removal"
        legacy = [{key: value for key, value in row.items() if key != "monitorIdentity"}]
        third = create_mapping_dialog(None, lambda: legacy, lambda rows: saved.append(rows), lambda: [
            {"id": "stable-custom", "name": "Custom editor"}])
        tree = next(widget for widget in children(third) if isinstance(widget, Gtk.TreeView))
        assert "choose monitor again" in tree.get_model()[0][2]
        tree.get_selection().select_path(Gtk.TreePath.new_from_indices([0]))
        GLib.timeout_add(200, fill_editor)
        button(third, "Edit…").emit("clicked")
        third.response(Gtk.ResponseType.OK)
        assert saved[1][0]["monitorIdentity"] == monitors[0]["identity"]
        assert saved[1][0]["layoutId"] == row["layoutId"]
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
