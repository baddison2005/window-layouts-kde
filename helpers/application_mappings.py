# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-3.0-or-later

"""Application launch mapping validation, process identities, and shared editor."""

import json
from pathlib import Path
import subprocess

MAX_MAPPINGS = 100
FIXED_LAYOUTS = (
    ("LeftHalf", "Left Half"), ("RightHalf", "Right Half"),
    ("TopHalf", "Top Half"), ("BottomHalf", "Bottom Half"),
    ("TopLeft", "Top Left"), ("TopRight", "Top Right"),
    ("BottomLeft", "Bottom Left"), ("BottomRight", "Bottom Right"),
    ("LeftThird", "Left Third"), ("CenterThird", "Center Third"),
    ("RightThird", "Right Third"), ("LeftTwoThirds", "Left Two Thirds"),
    ("CenterTwoThirds", "Center Two Thirds"), ("RightTwoThirds", "Right Two Thirds"),
)


def validated_mappings(value):
    """Reject ambiguous/invalid rules before replacing the saved configuration."""
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, list) or len(value) > MAX_MAPPINGS:
        raise ValueError(f"Specify at most {MAX_MAPPINGS} application mappings.")
    result, identities = [], set()
    for record in value:
        if not isinstance(record, dict):
            raise ValueError("Each application mapping must be an object.")
        item = {}
        for field in ("applicationId", "applicationName", "wmClass", "layoutId", "monitor", "titleIncludes"):
            text = record.get(field, "")
            if not isinstance(text, str) or len(text) > 512 or any(ord(c) < 32 for c in text):
                raise ValueError(f"Invalid {field} in application mapping.")
            item[field] = text.strip()
        if item["applicationId"].lower().endswith(".desktop"):
            item["applicationId"] = item["applicationId"][:-8]
        if not item["applicationId"] or not item["layoutId"] or not item["monitor"]:
            raise ValueError("Choose an application, layout, and monitor for every mapping.")
        identity = item["applicationId"].casefold()
        if identity in identities:
            raise ValueError("Only one launch mapping can be saved per application.")
        identities.add(identity)
        layout_id = item["layoutId"]
        if layout_id not in {f"WindowLayouts{key}" for key, _ in FIXED_LAYOUTS} and not (
            layout_id.startswith("custom:") and len(layout_id) > 7
        ):
            raise ValueError("Choose a fixed or custom layout.")
        requirement = record.get("windowRequirement", "firstEligibleWindow")
        if requirement not in ("firstEligibleWindow", "documentWindow"):
            raise ValueError("Choose a valid window readiness mode.")
        item["windowRequirement"] = requirement
        excluded = record.get("excludedTitles", [])
        if not isinstance(excluded, list) or len(excluded) > 30 or any(
            not isinstance(title, str) or not title.strip() or len(title) > 200
            or any(ord(c) < 32 for c in title) for title in excluded
        ):
            raise ValueError("Excluded titles must be a list of up to 30 nonempty title fragments.")
        item["excludedTitles"] = [title.strip() for title in excluded]
        result.append(item)
    return result


def process_token(pid, proc_root=Path("/proc")):
    """Return PID + Linux process start tick, never process command lines."""
    try:
        pid = int(pid)
        if pid <= 0:
            return ""
        data = (proc_root / str(pid) / "stat").read_text(encoding="utf-8")
        # comm is parenthesized and can itself contain spaces and parentheses.
        fields = data[data.rfind(")") + 2:].split()
        if fields[0] in ("Z", "X"):
            return ""
        return f"{pid}:{int(fields[19])}"
    except (OSError, ValueError, IndexError):
        return ""


def inspect_launch_process(pid, encoded_previous, proc_root=Path("/proc")):
    previous = json.loads(encoded_previous)
    if not isinstance(previous, list) or len(previous) > 256:
        raise ValueError("Invalid launch process list.")
    alive = []
    for token in previous:
        if not isinstance(token, str) or len(token) > 64:
            continue
        process_id, separator, _ = token.partition(":")
        if separator and process_token(process_id, proc_root) == token:
            alive.append(token)
    token = process_token(pid, proc_root)
    previous_alive = bool(alive)
    if token and token not in alive:
        alive.append(token)
    return {"token": token, "previousAlive": previous_alive, "processes": alive}


def connected_monitors():
    try:
        completed = subprocess.run(["kscreen-doctor", "-j"], check=True,
                                   capture_output=True, text=True, timeout=5)
        outputs = json.loads(completed.stdout).get("outputs", [])
        return [output["name"] for output in outputs
                if output.get("connected") and output.get("enabled") and output.get("name")]
    except (OSError, subprocess.SubprocessError, ValueError, TypeError):
        return []


def create_mapping_dialog(parent, load, save, load_layouts):
    """One shared editor for Plasma, the floating button, and Cairo-Dock."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, Gtk

    dialog = Gtk.Dialog(title="Application Launch Mappings", transient_for=parent,
                        modal=True, destroy_with_parent=True)
    dialog.set_default_size(800, 500)
    dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.OK)
    content = dialog.get_content_area()
    content.set_spacing(10)
    content.set_border_width(12)
    explanation = Gtk.Label(xalign=0, wrap=True, label=(
        "Place the first ready window after a fresh application launch. Existing windows "
        "and later windows from the same running app stay where they are. Mappings arm "
        "30 seconds after Window Layouts starts and wait up to 5 minutes for a ready window.\n"
        "Use Document window for apps with launchers or template choosers. For unusual "
        "or localized launch screens, add excluded titles or require a title fragment. "
        "These mappings are saved separately when you select Save here."
    ))
    content.pack_start(explanation, False, False, 0)
    rows = list(load())
    model = Gtk.ListStore(str, str, str, str)
    tree = Gtk.TreeView(model=model)
    tree.get_selection().set_mode(Gtk.SelectionMode.SINGLE)
    for index, title in enumerate(("Application", "Layout", "Monitor", "Ready window")):
        column = Gtk.TreeViewColumn(title, Gtk.CellRendererText(), text=index)
        column.set_expand(True)
        tree.append_column(column)
    scroller = Gtk.ScrolledWindow()
    scroller.set_vexpand(True)
    scroller.add(tree)
    content.pack_start(scroller, True, True, 0)
    buttons = Gtk.Box(spacing=8)
    content.pack_start(buttons, False, False, 0)
    status = Gtk.Label(xalign=0, wrap=True)
    content.pack_start(status, False, False, 0)

    def layout_choices():
        return [(f"WindowLayouts{key}", label) for key, label in FIXED_LAYOUTS] + [
            (f"custom:{item['id']}", item["name"]) for item in load_layouts() if item.get("id")
        ]

    def refresh():
        names = dict(layout_choices())
        model.clear()
        for item in rows:
            model.append((item["applicationName"] or item["applicationId"],
                          names.get(item["layoutId"], "Unavailable custom layout"), item["monitor"],
                          "Document window" if item["windowRequirement"] == "documentWindow"
                          else "First eligible window"))

    def selected_index():
        selected_model, selected = tree.get_selection().get_selected()
        return selected_model.get_path(selected).get_indices()[0] if selected else None

    def edit(_button=None, add=False):
        index = None if add else selected_index()
        if not add and index is None:
            return
        item = rows[index] if index is not None else {}
        editor = Gtk.Dialog(title="Launch Mapping", transient_for=dialog, modal=True)
        editor.set_default_size(650, 420)
        editor.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Use Mapping", Gtk.ResponseType.OK)
        grid = Gtk.Grid(column_spacing=12, row_spacing=10, margin=15)
        editor.get_content_area().add(grid)
        app = Gtk.ComboBoxText.new_with_entry()
        apps = {}
        for info in sorted(Gio.AppInfo.get_all(), key=lambda entry: entry.get_display_name().casefold()):
            if info.should_show() and info.get_id():
                app_id = info.get_id().removesuffix(".desktop")
                wm_class = info.get_string("StartupWMClass") if hasattr(info, "get_string") else ""
                apps[app_id] = (info.get_display_name(), wm_class or "")
                app.append(app_id, f"{info.get_display_name()} ({app_id})")
        if item.get("applicationId") in apps:
            app.set_active_id(item["applicationId"])
        else:
            app.get_child().set_text(item.get("applicationId", ""))
        layout = Gtk.ComboBoxText()
        choices = layout_choices()
        for layout_id, label in choices:
            layout.append(layout_id, label)
        if item.get("layoutId") and item["layoutId"] not in dict(choices):
            layout.append(item["layoutId"], "Unavailable custom layout (choose another)")
        layout.set_active_id(item.get("layoutId", choices[0][0]))
        monitor = Gtk.ComboBoxText.new_with_entry()
        for name in connected_monitors():
            monitor.append_text(name)
        monitor.get_child().set_text(item.get("monitor", ""))
        if not item.get("monitor") and monitor.get_model().iter_n_children(None):
            monitor.set_active(0)
        requirement = Gtk.ComboBoxText()
        requirement.append("firstEligibleWindow", "First eligible window")
        requirement.append("documentWindow", "Document window (wait past launchers / choosers)")
        requirement.set_active_id(item.get("windowRequirement", "firstEligibleWindow"))
        title = Gtk.Entry(text=item.get("titleIncludes", ""))
        title.set_placeholder_text("Optional: text that must occur in the actual window title")
        excluded = Gtk.Entry(text="; ".join(item.get("excludedTitles", [])))
        excluded.set_placeholder_text("Optional: title fragments separated by semicolons")
        for row, (label, control) in enumerate((
            ("Application", app), ("Layout", layout), ("Monitor connector", monitor),
            ("Wait for", requirement), ("Required title text", title), ("Ignore titles containing", excluded),
        )):
            grid.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1)
            control.set_hexpand(True)
            grid.attach(control, 1, row, 1, 1)
        hint = Gtk.Label(xalign=0, wrap=True, label=(
            "Select an installed application or enter its desktop ID / WM_CLASS. "
            "Missing monitors and deleted custom layouts are skipped. Document detection "
            "uses window roles and titles; required title text gives stricter control."
        ))
        grid.attach(hint, 0, 6, 2, 1)
        error_label = Gtk.Label(xalign=0, wrap=True)
        grid.attach(error_label, 0, 7, 2, 1)
        editor.show_all()
        while editor.run() == Gtk.ResponseType.OK:
            app_id = app.get_active_id() or app.get_child().get_text().strip()
            app_name, wm_class = apps.get(app_id, (app_id, ""))
            candidate = {
                "applicationId": app_id, "applicationName": app_name, "wmClass": wm_class,
                "layoutId": layout.get_active_id() or "", "monitor": monitor.get_child().get_text(),
                "windowRequirement": requirement.get_active_id(), "titleIncludes": title.get_text(),
                "excludedTitles": [text.strip() for text in excluded.get_text().split(";") if text.strip()],
            }
            updated = list(rows)
            if index is None:
                updated.append(candidate)
            else:
                updated[index] = candidate
            try:
                updated = validated_mappings(updated)
            except (ValueError, TypeError) as error:
                error_label.set_text(str(error))
                continue
            rows[:] = updated
            refresh()
            break
        editor.destroy()

    def remove(_button):
        index = selected_index()
        if index is not None:
            del rows[index]
            refresh()

    for title, callback in (("Add…", lambda button: edit(button, True)), ("Edit…", edit), ("Remove", remove)):
        button = Gtk.Button(label=title)
        button.connect("clicked", callback)
        buttons.pack_start(button, False, False, 0)
    tree.connect("row-activated", lambda *_args: edit())

    def response(_dialog, response_id):
        if response_id == Gtk.ResponseType.OK:
            try:
                save(validated_mappings(rows))
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                status.set_text(f"Could not save mappings: {error}")
                return
        dialog.destroy()

    refresh()
    dialog.connect("response", response)
    dialog.show_all()
    return dialog
