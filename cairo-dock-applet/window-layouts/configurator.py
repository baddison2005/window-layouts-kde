#!/usr/bin/python3

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-3.0-or-later

"""Shared GTK configurator for the Window Layouts frontends."""

import gi
from pathlib import Path
import threading
import time

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk


GRID_COLUMNS = 24
GRID_ROWS = 12
MAX_LAYOUTS = 20
APP_VERSION = "1.2.1"
PROJECT_URL = "https://github.com/baddison2005/window-layouts-kde"
HELP_URL = f"{PROJECT_URL}/issues"
RELEASES_URL = f"{PROJECT_URL}/releases"
LOGO_PATH = Path(__file__).resolve().with_name("window-layouts.svg")
DEFAULT_GROUP_ORDER = (
    "halves",
    "quarters",
    "thirds",
    "twoThirds",
    "custom",
    "fillDisplay",
    "window",
)
GROUP_LABELS = {
    "halves": "Halves",
    "quarters": "Quarters",
    "thirds": "Thirds",
    "twoThirds": "Two Thirds",
    "custom": "Custom",
    "fillDisplay": "Fill Display",
    "window": "Window",
}
QT_SHIFT = 0x02000000
QT_CONTROL = 0x04000000
QT_ALT = 0x08000000
QT_META = 0x10000000
QT_KEY_MASK = 0x01FFFFFF
GDK_TO_QT_KEY = {
    Gdk.KEY_Escape: 0x01000000,
    Gdk.KEY_Tab: 0x01000001,
    Gdk.KEY_ISO_Left_Tab: 0x01000002,
    Gdk.KEY_BackSpace: 0x01000003,
    Gdk.KEY_Return: 0x01000004,
    Gdk.KEY_KP_Enter: 0x01000005,
    Gdk.KEY_Insert: 0x01000006,
    Gdk.KEY_Delete: 0x01000007,
    Gdk.KEY_Home: 0x01000010,
    Gdk.KEY_End: 0x01000011,
    Gdk.KEY_Left: 0x01000012,
    Gdk.KEY_Up: 0x01000013,
    Gdk.KEY_Right: 0x01000014,
    Gdk.KEY_Down: 0x01000015,
    Gdk.KEY_Page_Up: 0x01000016,
    Gdk.KEY_Page_Down: 0x01000017,
}
for _function_number in range(1, 36):
    GDK_TO_QT_KEY[getattr(Gdk, f"KEY_F{_function_number}")] = (
        0x01000030 + _function_number - 1
    )
QT_TO_GDK_KEY = {value: key for key, value in GDK_TO_QT_KEY.items()}


def gtk_accelerator_to_qt(keyval, modifiers):
    """Convert GTK's accelerator representation to Qt's combined key value."""
    qt_key = GDK_TO_QT_KEY.get(keyval)
    if qt_key is None:
        unicode_value = Gdk.keyval_to_unicode(keyval)
        if not unicode_value:
            raise ValueError("That key is not supported by Window Layouts")
        qt_key = ord(chr(unicode_value).upper())
    combined = qt_key
    if modifiers & Gdk.ModifierType.SHIFT_MASK:
        combined |= QT_SHIFT
    if modifiers & Gdk.ModifierType.CONTROL_MASK:
        combined |= QT_CONTROL
    if modifiers & Gdk.ModifierType.MOD1_MASK:
        combined |= QT_ALT
    if modifiers & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.META_MASK):
        combined |= QT_META
    return combined


def qt_to_gtk_accelerator(combined):
    """Convert Qt's combined key value for display by Gtk.CellRendererAccel."""
    combined = int(combined)
    key = combined & QT_KEY_MASK
    keyval = QT_TO_GDK_KEY.get(key)
    if keyval is None and 0x20 <= key <= 0x10FFFF:
        keyval = Gdk.unicode_to_keyval(ord(chr(key).lower()))
    if keyval is None:
        keyval = 0
    modifiers = Gdk.ModifierType(0)
    if combined & QT_SHIFT:
        modifiers |= Gdk.ModifierType.SHIFT_MASK
    if combined & QT_CONTROL:
        modifiers |= Gdk.ModifierType.CONTROL_MASK
    if combined & QT_ALT:
        modifiers |= Gdk.ModifierType.MOD1_MASK
    if combined & QT_META:
        modifiers |= Gdk.ModifierType.SUPER_MASK
    return keyval, modifiers


class LayoutGrid(Gtk.DrawingArea):
    """A draggable selection grid matching the Plasma configurator."""

    def __init__(self, changed_callback):
        super().__init__()
        self.changed_callback = changed_callback
        self.selection = (0, 0, 12, 6)
        self.drag_start = None
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_size_request(600, 360)
        self.add_events(
            Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
        )
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._button_press)
        self.connect("button-release-event", self._button_release)
        self.connect("motion-notify-event", self._motion)

    def set_selection(self, column, row, column_span, row_span):
        self.selection = (column, row, column_span, row_span)
        self.queue_draw()

    def _cell_at(self, x, y):
        allocation = self.get_allocation()
        column = max(0, min(
            GRID_COLUMNS - 1,
            int(x * GRID_COLUMNS / max(1, allocation.width)),
        ))
        row = max(0, min(
            GRID_ROWS - 1,
            int(y * GRID_ROWS / max(1, allocation.height)),
        ))
        return column, row

    def _select_to(self, column, row):
        if self.drag_start is None:
            return
        start_column, start_row = self.drag_start
        left = min(start_column, column)
        top = min(start_row, row)
        right = max(start_column, column)
        bottom = max(start_row, row)
        self.selection = (
            left,
            top,
            right - left + 1,
            bottom - top + 1,
        )
        self.changed_callback(*self.selection)
        self.queue_draw()

    def _button_press(self, _widget, event):
        if event.button != Gdk.BUTTON_PRIMARY:
            return False
        self.drag_start = self._cell_at(event.x, event.y)
        self._select_to(*self.drag_start)
        return True

    def _motion(self, _widget, event):
        if self.drag_start is None:
            return False
        self._select_to(*self._cell_at(event.x, event.y))
        return True

    def _button_release(self, _widget, event):
        if event.button != Gdk.BUTTON_PRIMARY or self.drag_start is None:
            return False
        self._select_to(*self._cell_at(event.x, event.y))
        self.drag_start = None
        return True

    def _draw(self, widget, context):
        allocation = self.get_allocation()
        width = allocation.width
        height = allocation.height
        style = widget.get_style_context()
        Gtk.render_background(style, context, 0, 0, width, height)

        column, row, column_span, row_span = self.selection
        cell_width = width / GRID_COLUMNS
        cell_height = height / GRID_ROWS
        context.set_source_rgba(0.20, 0.55, 0.95, 0.35)
        context.rectangle(
            column * cell_width,
            row * cell_height,
            column_span * cell_width,
            row_span * cell_height,
        )
        context.fill()

        foreground = style.get_color(Gtk.StateFlags.NORMAL)
        context.set_source_rgba(
            foreground.red,
            foreground.green,
            foreground.blue,
            0.35,
        )
        context.set_line_width(1)
        for grid_column in range(GRID_COLUMNS + 1):
            x = round(grid_column * cell_width) + 0.5
            context.move_to(x, 0)
            context.line_to(x, height)
        for grid_row in range(GRID_ROWS + 1):
            y = round(grid_row * cell_height) + 0.5
            context.move_to(0, y)
            context.line_to(width, y)
        context.stroke()

        context.set_source_rgba(0.20, 0.55, 0.95, 0.95)
        context.set_line_width(2)
        context.rectangle(
            column * cell_width + 1,
            row * cell_height + 1,
            column_span * cell_width - 2,
            row_span * cell_height - 2,
        )
        context.stroke()
        return False


class WindowLayoutsConfigurator(Gtk.Window):
    """Edit named layouts and persist them through applet callbacks."""

    def __init__(
        self,
        load_callback,
        save_callback,
        load_settings_callback=None,
        save_settings_callback=None,
        load_groups_callback=None,
        save_groups_callback=None,
        load_shortcuts_callback=None,
        save_shortcut_callback=None,
        check_updates_callback=None,
        install_update_callback=None,
    ):
        super().__init__(title="Configure Window Layouts")
        self.load_callback = load_callback
        self.save_callback = save_callback
        self.load_settings_callback = load_settings_callback or (lambda: {})
        self.save_settings_callback = save_settings_callback or (lambda _settings: None)
        self.load_groups_callback = load_groups_callback or (lambda: [])
        self.save_groups_callback = save_groups_callback or (lambda _groups: None)
        self.load_shortcuts_callback = load_shortcuts_callback or (lambda: [])
        self.save_shortcut_callback = save_shortcut_callback
        self.check_updates_callback = check_updates_callback
        self.install_update_callback = install_update_callback
        self.layouts = []
        self.custom_groups = []
        self.group_order = list(DEFAULT_GROUP_ORDER)
        self.selected_group_index = 0
        self.selected_index = -1
        self._layout_rows = {}
        self.updating_controls = False
        self.dirty = False

        self.set_default_size(960, 800)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_keep_above(True)
        self.connect("delete-event", self._hide_window)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.set_border_width(12)
        self.add(root)

        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        root.pack_start(content, True, True, 0)

        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        left.set_size_request(250, -1)
        content.pack_start(left, False, False, 0)

        saved_label = Gtk.Label(label="Saved layouts", xalign=0)
        saved_label.get_style_context().add_class("heading")
        left.pack_start(saved_label, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        left.pack_start(scroller, True, True, 0)

        self.layout_list = Gtk.ListBox()
        self.layout_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.layout_list.connect("row-selected", self._row_selected)
        scroller.add(self.layout_list)

        list_buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        left.pack_start(list_buttons, False, False, 0)
        self.add_button = self._button("Add", "list-add", self._add_layout)
        self.remove_button = self._button("Remove", "list-remove", self._remove_layout)
        self.up_button = self._button("Up", "go-up", self._move_up)
        self.down_button = self._button("Down", "go-down", self._move_down)
        for button in (
            self.add_button,
            self.remove_button,
            self.up_button,
            self.down_button,
        ):
            list_buttons.pack_start(button, True, True, 0)

        self.layout_count_label = Gtk.Label(xalign=0)
        left.pack_start(self.layout_count_label, False, False, 0)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        content.pack_start(right, True, True, 0)

        name_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        right.pack_start(name_row, False, False, 0)
        name_row.pack_start(Gtk.Label(label="Name:"), False, False, 0)
        self.name_entry = Gtk.Entry()
        self.name_entry.connect("changed", self._name_changed)
        name_row.pack_start(self.name_entry, True, True, 0)

        custom_group_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        right.pack_start(custom_group_row, False, False, 0)
        custom_group_row.pack_start(Gtk.Label(label="Custom group:"), False, False, 0)
        self.custom_group_combo = Gtk.ComboBoxText()
        self.custom_group_combo.connect("changed", self._custom_group_changed)
        custom_group_row.pack_start(self.custom_group_combo, True, True, 0)
        for label, icon, callback in (
            ("New group", "list-add", self._new_custom_group),
            ("Rename group", "document-edit", self._rename_custom_group),
            ("Remove group", "edit-delete", self._remove_custom_group),
        ):
            button = self._button(label, icon, callback)
            button.set_tooltip_text(label)
            custom_group_row.pack_start(button, False, False, 0)
            if label == "Rename group":
                self.rename_custom_group_button = button
            elif label == "Remove group":
                self.remove_custom_group_button = button

        shortcut_button = self._button(
            "Keyboard Shortcuts…", "preferences-desktop-keyboard", self._show_shortcuts
        )
        custom_group_row.pack_start(shortcut_button, False, False, 0)

        help_label = Gtk.Label(
            label="Drag across the grid to choose the window's position and size.",
            xalign=0,
        )
        help_label.set_line_wrap(True)
        right.pack_start(help_label, False, False, 0)

        frame = Gtk.Frame()
        right.pack_start(frame, True, True, 0)
        self.grid = LayoutGrid(self._grid_changed)
        frame.add(self.grid)

        self.geometry_label = Gtk.Label(xalign=0)
        right.pack_start(self.geometry_label, False, False, 0)

        preferences_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        root.pack_start(preferences_box, False, False, 0)

        group_order_frame = Gtk.Frame(label="Layout group order")
        group_order_frame.set_size_request(300, -1)
        preferences_box.pack_start(group_order_frame, False, False, 0)
        group_order_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        group_order_box.set_border_width(10)
        group_order_frame.add(group_order_box)

        self.group_order_list = Gtk.ListBox()
        self.group_order_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.group_order_list.set_size_request(190, 150)
        self.group_order_list.connect("row-selected", self._group_row_selected)
        group_order_box.pack_start(self.group_order_list, True, True, 0)

        group_button_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        group_order_box.pack_start(group_button_box, False, False, 0)
        self.group_up_button = self._button("Up", "go-up", self._move_group_up)
        self.group_down_button = self._button("Down", "go-down", self._move_group_down)
        group_button_box.pack_start(self.group_up_button, False, False, 0)
        group_button_box.pack_start(self.group_down_button, False, False, 0)

        features_frame = Gtk.Frame(label="Features")
        preferences_box.pack_start(features_frame, True, True, 0)
        features_grid = Gtk.Grid()
        features_grid.set_border_width(10)
        features_grid.set_column_spacing(16)
        features_grid.set_row_spacing(8)
        features_frame.add(features_grid)

        floating_label = Gtk.Label(
            label="Show the floating button beside the active window",
            xalign=0,
        )
        floating_label.set_hexpand(True)
        features_grid.attach(floating_label, 0, 0, 1, 1)
        self.floating_button_switch = Gtk.Switch()
        self.floating_button_switch.set_halign(Gtk.Align.END)
        self.floating_button_switch.connect("notify::active", self._feature_changed)
        features_grid.attach(self.floating_button_switch, 1, 0, 1, 1)

        floating_size_label = Gtk.Label(label="Floating button size", xalign=0)
        floating_size_label.set_margin_start(20)
        floating_size_label.set_hexpand(True)
        features_grid.attach(floating_size_label, 0, 1, 1, 1)
        self.floating_button_size_combo = Gtk.ComboBoxText()
        for size_id, size_label in (
            ("small", "Small"),
            ("default", "Default"),
            ("big", "Big"),
            ("extraBig", "Extra big"),
        ):
            self.floating_button_size_combo.append(size_id, size_label)
        self.floating_button_size_combo.set_halign(Gtk.Align.END)
        self.floating_button_size_combo.connect("changed", self._feature_changed)
        features_grid.attach(self.floating_button_size_combo, 1, 1, 1, 1)

        drag_targets_label = Gtk.Label(
            label="Show layout targets while dragging a window",
            xalign=0,
        )
        drag_targets_label.set_hexpand(True)
        features_grid.attach(drag_targets_label, 0, 2, 1, 1)
        self.drag_targets_switch = Gtk.Switch()
        self.drag_targets_switch.set_halign(Gtk.Align.END)
        self.drag_targets_switch.connect("notify::active", self._feature_changed)
        features_grid.attach(self.drag_targets_switch, 1, 2, 1, 1)

        self.zone_targets_radio = Gtk.RadioButton.new_with_label_from_widget(
            None,
            "Layout targets at the center of each layout zone",
        )
        self.zone_targets_radio.set_halign(Gtk.Align.START)
        self.zone_targets_radio.set_margin_start(20)
        self.zone_targets_radio.connect("toggled", self._feature_changed)
        features_grid.attach(self.zone_targets_radio, 0, 3, 2, 1)

        show_all_zone_targets_label = Gtk.Label(
            label="Display zone targets immediately",
            xalign=0,
        )
        show_all_zone_targets_label.set_margin_start(40)
        show_all_zone_targets_label.set_hexpand(True)
        features_grid.attach(show_all_zone_targets_label, 0, 4, 1, 1)
        self.show_all_zone_targets_switch = Gtk.Switch()
        self.show_all_zone_targets_switch.set_halign(Gtk.Align.END)
        self.show_all_zone_targets_switch.connect(
            "notify::active",
            self._feature_changed,
        )
        features_grid.attach(self.show_all_zone_targets_switch, 1, 4, 1, 1)

        self.top_targets_radio = Gtk.RadioButton.new_with_label_from_widget(
            self.zone_targets_radio,
            "Layout targets in a top-center strip",
        )
        self.top_targets_radio.set_halign(Gtk.Align.START)
        self.top_targets_radio.set_margin_start(20)
        self.top_targets_radio.connect("toggled", self._feature_changed)
        features_grid.attach(self.top_targets_radio, 0, 5, 2, 1)

        show_all_top_targets_label = Gtk.Label(
            label="Display the top-center strip immediately",
            xalign=0,
        )
        show_all_top_targets_label.set_margin_start(40)
        show_all_top_targets_label.set_hexpand(True)
        features_grid.attach(show_all_top_targets_label, 0, 6, 1, 1)
        self.show_all_top_targets_switch = Gtk.Switch()
        self.show_all_top_targets_switch.set_halign(Gtk.Align.END)
        self.show_all_top_targets_switch.connect(
            "notify::active",
            self._feature_changed,
        )
        features_grid.attach(self.show_all_top_targets_switch, 1, 6, 1, 1)

        layout_padding_label = Gtk.Label(
            label="Layout padding (pixels)",
            xalign=0,
        )
        layout_padding_label.set_hexpand(True)
        features_grid.attach(layout_padding_label, 0, 7, 1, 1)
        self.layout_padding_spin = Gtk.SpinButton.new_with_range(0, 200, 1)
        self.layout_padding_spin.set_numeric(True)
        self.layout_padding_spin.set_halign(Gtk.Align.END)
        self.layout_padding_spin.connect("value-changed", self._feature_changed)
        features_grid.attach(self.layout_padding_spin, 1, 7, 1, 1)

        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        root.pack_start(footer, False, False, 0)
        about_button = self._button(
            "About & Updates…", "help-about", self._show_about
        )
        footer.pack_start(about_button, False, False, 0)
        self.status_label = Gtk.Label(xalign=0)
        footer.pack_start(self.status_label, True, True, 0)
        self.ok_button = self._button("OK", "dialog-ok", self._ok)
        self.apply_button = self._button("Apply", "dialog-ok-apply", self._apply)
        cancel_button = self._button("Cancel", "dialog-cancel", self._cancel)
        self.apply_button.set_sensitive(False)
        footer.pack_start(self.ok_button, False, False, 0)
        footer.pack_start(self.apply_button, False, False, 0)
        footer.pack_start(cancel_button, False, False, 0)

    @staticmethod
    def _button(label, icon_name, callback):
        button = Gtk.Button.new_with_label(label)
        button.set_image(Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON))
        button.set_always_show_image(True)
        if callback is not None:
            button.connect("clicked", callback)
        return button

    @staticmethod
    def _run_background(callback, finished_callback):
        """Run network and installer work without blocking GTK's event loop."""
        def worker():
            try:
                result = callback()
            except Exception as error:  # callbacks return user-facing errors
                result = {"error": str(error)}
            GLib.idle_add(finished_callback, result)

        threading.Thread(target=worker, daemon=True).start()

    def _show_about(self, _button):
        dialog = Gtk.Dialog(
            title="About Window Layouts",
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
        )
        dialog.add_button("Close", Gtk.ResponseType.CLOSE)
        dialog.set_default_size(620, 520)
        content = dialog.get_content_area()
        content.set_border_width(18)
        content.set_spacing(14)

        identity = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=18)
        content.pack_start(identity, False, False, 0)
        if LOGO_PATH.is_file():
            logo = Gtk.Image.new_from_file(str(LOGO_PATH))
        else:
            logo = Gtk.Image.new_from_icon_name("view-grid", Gtk.IconSize.DIALOG)
        logo.set_pixel_size(96)
        identity.pack_start(logo, False, False, 0)

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        identity.pack_start(title_box, True, True, 0)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<span size='xx-large'><b>Window Layouts {APP_VERSION}</b></span>")
        title_box.pack_start(title, False, False, 0)
        slogan = Gtk.Label(xalign=0)
        slogan.set_markup(
            "<span size='large'><b>Your Workspace, Organized Your Way!</b></span>"
        )
        slogan.set_line_wrap(True)
        title_box.pack_start(slogan, False, False, 0)
        description = Gtk.Label(
            label="Flexible window positioning and layouts for KDE Plasma Wayland.",
            xalign=0,
        )
        description.set_line_wrap(True)
        title_box.pack_start(description, False, False, 0)

        details = Gtk.Grid(column_spacing=16, row_spacing=10)
        content.pack_start(details, False, False, 0)
        for row, (heading, widget) in enumerate((
            ("Author", Gtk.Label(label="Dr. Bret Addison", xalign=0)),
            ("Website", Gtk.LinkButton.new_with_label(PROJECT_URL, PROJECT_URL)),
            ("Get Help", Gtk.LinkButton.new_with_label(HELP_URL, "Report an issue on GitHub")),
        )):
            heading_label = Gtk.Label(xalign=0)
            heading_label.set_markup(f"<b>{heading}</b>")
            details.attach(heading_label, 0, row, 1, 1)
            widget.set_halign(Gtk.Align.START)
            details.attach(widget, 1, row, 1, 1)

        separator = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        content.pack_start(separator, False, False, 2)
        update_heading = Gtk.Label(xalign=0)
        update_heading.set_markup("<span size='large'><b>Software Updates</b></span>")
        content.pack_start(update_heading, False, False, 0)
        update_help = Gtk.Label(
            label=(
                "Check GitHub Releases for a newer stable version. Updates are "
                "downloaded over HTTPS and installed only after their published "
                "SHA-256 checksum has been verified."
            ),
            xalign=0,
        )
        update_help.set_line_wrap(True)
        content.pack_start(update_help, False, False, 0)

        update_status = Gtk.Label(
            label=f"Installed version: {APP_VERSION}",
            xalign=0,
        )
        update_status.set_line_wrap(True)
        update_status.set_selectable(True)
        content.pack_start(update_status, False, False, 0)

        update_actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        content.pack_start(update_actions, False, False, 0)
        spinner = Gtk.Spinner()
        update_actions.pack_start(spinner, False, False, 0)
        check_button = self._button("Check for Updates", "view-refresh", None)
        install_button = self._button(
            "Install Update", "software-update-available", None
        )
        install_button.set_sensitive(False)
        releases_button = Gtk.LinkButton.new_with_label(
            RELEASES_URL, "View GitHub Releases"
        )
        update_actions.pack_start(check_button, False, False, 0)
        update_actions.pack_start(install_button, False, False, 0)
        update_actions.pack_end(releases_button, False, False, 0)

        state = {"destroyed": False, "latest": ""}
        dialog.connect("destroy", lambda *_args: state.update(destroyed=True))

        def set_busy(busy):
            check_button.set_sensitive(not busy and self.check_updates_callback is not None)
            install_button.set_sensitive(
                not busy and bool(state["latest"])
            )
            if busy:
                spinner.start()
            else:
                spinner.stop()

        def check_finished(result):
            if state["destroyed"]:
                return GLib.SOURCE_REMOVE
            set_busy(False)
            if result.get("error"):
                state["latest"] = ""
                install_button.set_sensitive(False)
                update_status.set_text(f"Could not check for updates: {result['error']}")
            elif result.get("updateAvailable"):
                if result.get("canInstall"):
                    state["latest"] = result.get("latestVersion", "")
                    install_button.set_label(
                        f"Install v{state['latest']}"
                    )
                    install_button.set_sensitive(True)
                    update_status.set_text(
                        f"Window Layouts {state['latest']} is available."
                    )
                else:
                    state["latest"] = ""
                    install_button.set_sensitive(False)
                    update_status.set_text(
                        result.get("installReason") or "A manual update is available."
                    )
            else:
                state["latest"] = ""
                install_button.set_sensitive(False)
                update_status.set_text(
                    f"Window Layouts {APP_VERSION} is up to date."
                )
            return GLib.SOURCE_REMOVE

        def install_finished(result):
            if state["destroyed"]:
                return GLib.SOURCE_REMOVE
            set_busy(False)
            if result.get("error"):
                update_status.set_text(f"Could not install the update: {result['error']}")
            elif result.get("installed"):
                installed_version = result.get("latestVersion", state["latest"])
                state["latest"] = ""
                install_button.set_sensitive(False)
                update_status.set_text(
                    f"Window Layouts {installed_version} was installed. "
                    "Close and reopen Configure Window Layouts to load its updated About page."
                )
            else:
                state["latest"] = ""
                install_button.set_sensitive(False)
                update_status.set_text("Window Layouts is already up to date.")
            return GLib.SOURCE_REMOVE

        def check_clicked(_clicked_button):
            if self.check_updates_callback is None:
                update_status.set_text("The update service is unavailable.")
                return
            state["latest"] = ""
            set_busy(True)
            update_status.set_text("Checking GitHub Releases…")
            self._run_background(self.check_updates_callback, check_finished)

        def install_clicked(_clicked_button):
            if self.install_update_callback is None or not state["latest"]:
                return
            prompt = Gtk.MessageDialog(
                transient_for=dialog,
                modal=True,
                message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.NONE,
                text=f"Install Window Layouts {state['latest']}?",
            )
            prompt.format_secondary_text(
                "Your existing layouts and feature settings will be preserved."
            )
            prompt.add_buttons(
                "Cancel", Gtk.ResponseType.CANCEL,
                "Install", Gtk.ResponseType.OK,
            )
            response = prompt.run()
            prompt.destroy()
            if response != Gtk.ResponseType.OK:
                return
            set_busy(True)
            update_status.set_text(
                f"Downloading, verifying, and installing {state['latest']}…"
            )
            self._run_background(self.install_update_callback, install_finished)

        check_button.connect("clicked", check_clicked)
        install_button.connect("clicked", install_clicked)
        check_button.set_sensitive(self.check_updates_callback is not None)
        dialog.show_all()
        spinner.stop()
        dialog.run()
        dialog.destroy()

    def _show_shortcuts(self, _button):
        if self.save_shortcut_callback is None:
            return
        dialog = Gtk.Dialog(
            title="Window Layout Keyboard Shortcuts",
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
        )
        dialog.add_button("Close", Gtk.ResponseType.CLOSE)
        dialog.set_default_size(600, 560)
        content = dialog.get_content_area()
        content.set_border_width(12)
        help_label = Gtk.Label(
            label=(
                "Double-click a shortcut, then press the desired key combination. "
                "Clear it to remove the shortcut."
            ),
            xalign=0,
        )
        help_label.set_line_wrap(True)
        content.pack_start(help_label, False, False, 6)

        model = Gtk.ListStore(str, str, int, int)
        for entry in self.load_shortcuts_callback() or []:
            keyval, modifiers = qt_to_gtk_accelerator(entry.get("shortcut", 0))
            model.append([
                entry.get("label", entry.get("actionId", "")),
                entry.get("actionId", ""),
                keyval,
                int(modifiers),
            ])

        view = Gtk.TreeView(model=model)
        name_renderer = Gtk.CellRendererText()
        name_column = Gtk.TreeViewColumn("Layout", name_renderer, text=0)
        name_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        name_column.set_fixed_width(300)
        view.append_column(name_column)
        accel_renderer = Gtk.CellRendererAccel()
        accel_renderer.set_property("editable", True)
        accel_renderer.set_property("accel-mode", Gtk.CellRendererAccelMode.GTK)
        accel_renderer.connect("accel-edited", self._shortcut_edited, model, dialog)
        accel_renderer.connect("accel-cleared", self._shortcut_cleared, model, dialog)
        shortcut_column = Gtk.TreeViewColumn(
            "Shortcut", accel_renderer, accel_key=2, accel_mods=3
        )
        shortcut_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        shortcut_column.set_fixed_width(260)
        shortcut_column.set_expand(True)
        view.append_column(shortcut_column)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroller.add(view)
        content.pack_start(scroller, True, True, 6)
        dialog.show_all()
        dialog.run()
        dialog.destroy()

    def _shortcut_edited(
        self, _renderer, path, keyval, modifiers, _hardware_keycode, model, dialog
    ):
        try:
            shortcut = gtk_accelerator_to_qt(keyval, modifiers)
            iterator = model.get_iter(path)
            action_id = model.get_value(iterator, 1)
            result = self.save_shortcut_callback(action_id, shortcut, False)
            conflicts = result.get("conflicts", [])
            if conflicts:
                descriptions = "\n".join(
                    f"• {item['friendlyName']} ({item['componentFriendly']})"
                    for item in conflicts
                )
                prompt = Gtk.MessageDialog(
                    transient_for=dialog,
                    modal=True,
                    message_type=Gtk.MessageType.WARNING,
                    buttons=Gtk.ButtonsType.NONE,
                    text="Keyboard shortcut is already in use",
                )
                prompt.format_secondary_text(
                    f"This shortcut is assigned to:\n{descriptions}\n\n"
                    "Do you want to reassign it to this layout?"
                )
                prompt.add_buttons(
                    "Cancel", Gtk.ResponseType.CANCEL,
                    "Reassign", Gtk.ResponseType.OK,
                )
                response = prompt.run()
                prompt.destroy()
                if response != Gtk.ResponseType.OK:
                    return
                result = self.save_shortcut_callback(action_id, shortcut, True)
            if not result.get("changed", False):
                raise RuntimeError(result.get("error", "KDE rejected the shortcut"))
            model.set(iterator, 2, keyval, 3, int(modifiers))
        except Exception as error:
            message = Gtk.MessageDialog(
                transient_for=dialog,
                modal=True,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.CLOSE,
                text="Could not assign keyboard shortcut",
            )
            message.format_secondary_text(str(error))
            message.run()
            message.destroy()

    def _shortcut_cleared(self, _renderer, path, model, dialog):
        try:
            iterator = model.get_iter(path)
            action_id = model.get_value(iterator, 1)
            result = self.save_shortcut_callback(action_id, 0, True)
            if not result.get("changed", False):
                raise RuntimeError(result.get("error", "KDE rejected the change"))
            model.set(iterator, 2, 0, 3, 0)
        except Exception as error:
            message = Gtk.MessageDialog(
                transient_for=dialog,
                modal=True,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.CLOSE,
                text="Could not remove keyboard shortcut",
            )
            message.format_secondary_text(str(error))
            message.run()
            message.destroy()

    @staticmethod
    def _to_grid(layout):
        column = max(0, min(GRID_COLUMNS - 1, round(layout["x"] * GRID_COLUMNS)))
        row = max(0, min(GRID_ROWS - 1, round(layout["y"] * GRID_ROWS)))
        column_span = max(1, min(
            GRID_COLUMNS - column,
            round(layout["width"] * GRID_COLUMNS),
        ))
        row_span = max(1, min(
            GRID_ROWS - row,
            round(layout["height"] * GRID_ROWS),
        ))
        return {
            "name": layout["name"],
            "column": column,
            "row": row,
            "column_span": column_span,
            "row_span": row_span,
            "shortcut_slot": layout.get("shortcutSlot", 1),
            "group_id": layout.get("groupId", ""),
        }

    def show_configurator(self):
        self.custom_groups = list(self.load_groups_callback() or [])
        self.layouts = [self._to_grid(layout) for layout in self.load_callback()]
        settings = self.load_settings_callback() or {}
        self.updating_controls = True
        self.floating_button_switch.set_active(bool(
            settings.get("floating_button_enabled", False)
        ))
        self.drag_targets_switch.set_active(bool(
            settings.get("drag_targets_enabled", False)
        ))
        target_placement = settings.get("drag_target_placement", "zones")
        if target_placement not in ("zones", "top"):
            target_placement = "zones"
        self.zone_targets_radio.set_active(target_placement == "zones")
        self.top_targets_radio.set_active(target_placement == "top")
        self.show_all_zone_targets_switch.set_active(bool(
            settings.get("show_all_drag_targets", False)
        ))
        self.show_all_top_targets_switch.set_active(bool(
            settings.get("show_all_top_drag_targets", False)
        ))
        floating_button_size = settings.get("floating_button_size", "default")
        if floating_button_size not in ("small", "default", "big", "extraBig"):
            floating_button_size = "default"
        self.floating_button_size_combo.set_active_id(floating_button_size)
        try:
            layout_padding = int(settings.get("layout_padding", 0))
        except (TypeError, ValueError):
            layout_padding = 0
        self.layout_padding_spin.set_value(max(0, min(layout_padding, 200)))
        stored_group_order = settings.get("group_order", DEFAULT_GROUP_ORDER)
        self.group_order = self._validated_group_order(stored_group_order)
        self.selected_group_index = 0
        self.updating_controls = False
        self._update_feature_sensitivity()
        self._rebuild_group_list()
        self.selected_index = 0 if self.layouts else -1
        self.status_label.set_text("")
        self._set_dirty(False)
        self._rebuild_list()
        self._rebuild_custom_group_combo()
        self.show_all()
        self.present()

    def _hide_window(self, *_args):
        self._set_dirty(False)
        self.hide()
        return True

    def _cancel(self, _button):
        self._hide_window()

    def _set_dirty(self, dirty=True):
        self.dirty = dirty
        if hasattr(self, "apply_button"):
            self.apply_button.set_sensitive(dirty)
        if dirty and hasattr(self, "status_label"):
            self.status_label.set_text("")

    def _display_name(self, index):
        name = self.layouts[index]["name"].strip()
        return name or f"Custom Layout {index + 1}"

    def _grouped_layout_indices(self):
        """Return non-empty named groups followed by unassigned layouts."""
        valid_group_ids = {
            group.get("id") for group in self.custom_groups if group.get("id")
        }
        grouped = []
        for group in self.custom_groups:
            group_id = group.get("id")
            indices = [
                index for index, layout in enumerate(self.layouts)
                if layout.get("group_id", "") == group_id
            ]
            if indices:
                grouped.append((group.get("name") or "Custom group", indices))
        unassigned = [
            index for index, layout in enumerate(self.layouts)
            if not layout.get("group_id")
            or layout.get("group_id") not in valid_group_ids
        ]
        if unassigned:
            grouped.append(("Unassigned", unassigned))
        return grouped

    def _adjacent_layout_index(self, offset):
        if not 0 <= self.selected_index < len(self.layouts):
            return -1
        group_id = self.layouts[self.selected_index].get("group_id", "")
        index = self.selected_index + offset
        while 0 <= index < len(self.layouts):
            if self.layouts[index].get("group_id", "") == group_id:
                return index
            index += offset
        return -1

    def _rebuild_list(self):
        self.updating_controls = True
        for row in self.layout_list.get_children():
            self.layout_list.remove(row)
        self._layout_rows = {}
        for group_name, indices in self._grouped_layout_indices():
            heading_row = Gtk.ListBoxRow()
            heading_row.layout_index = -1
            heading_row.set_selectable(False)
            heading_row.set_activatable(False)
            heading = Gtk.Label(xalign=0)
            heading.set_markup(f"<b>{GLib.markup_escape_text(group_name)}</b>")
            heading.set_margin_top(6)
            heading.set_margin_bottom(3)
            heading_row.add(heading)
            self.layout_list.add(heading_row)

            for index in indices:
                row = Gtk.ListBoxRow()
                row.layout_index = index
                label = Gtk.Label(label=self._display_name(index), xalign=0)
                label.set_margin_start(14)
                row.add(label)
                self.layout_list.add(row)
                self._layout_rows[index] = row
        self.layout_list.show_all()
        selected_row = self._layout_rows.get(self.selected_index)
        if selected_row is not None:
            self.layout_list.select_row(selected_row)
        self.updating_controls = False
        self._load_selected_controls()

    def _load_selected_controls(self):
        valid = 0 <= self.selected_index < len(self.layouts)
        self.updating_controls = True
        self.name_entry.set_sensitive(valid)
        if valid:
            layout = self.layouts[self.selected_index]
            self.name_entry.set_text(layout["name"])
            self.grid.set_sensitive(True)
            self.grid.set_selection(
                layout["column"],
                layout["row"],
                layout["column_span"],
                layout["row_span"],
            )
            self._select_custom_group(layout.get("group_id", ""))
        else:
            self.name_entry.set_text("")
            self.grid.set_sensitive(False)
            self.custom_group_combo.set_active(0)
        self.updating_controls = False
        self.add_button.set_sensitive(len(self.layouts) < MAX_LAYOUTS)
        self.remove_button.set_sensitive(valid)
        self.up_button.set_sensitive(self._adjacent_layout_index(-1) >= 0)
        self.down_button.set_sensitive(self._adjacent_layout_index(1) >= 0)
        count = len(self.layouts)
        noun = "layout" if count == 1 else "layouts"
        self.layout_count_label.set_text(f"{count} of {MAX_LAYOUTS} {noun}")
        self._update_geometry_label()

    def _rebuild_custom_group_combo(self):
        current_group = ""
        if 0 <= self.selected_index < len(self.layouts):
            current_group = self.layouts[self.selected_index].get("group_id", "")
        self.updating_controls = True
        self.custom_group_combo.remove_all()
        self.custom_group_combo.append("", "Unassigned")
        valid_ids = {""}
        for group in self.custom_groups:
            group_id = group.get("id")
            name = group.get("name")
            if isinstance(group_id, str) and group_id and isinstance(name, str) and name:
                self.custom_group_combo.append(group_id, name)
                valid_ids.add(group_id)
        if current_group not in valid_ids and 0 <= self.selected_index < len(self.layouts):
            self.layouts[self.selected_index]["group_id"] = ""
            current_group = ""
        self.custom_group_combo.set_active_id(current_group)
        self.updating_controls = False
        self._update_custom_group_buttons()

    def _select_custom_group(self, group_id):
        self.custom_group_combo.set_active_id(group_id or "")
        if self.custom_group_combo.get_active() < 0:
            self.custom_group_combo.set_active_id("")
        self._update_custom_group_buttons()

    def _update_custom_group_buttons(self):
        has_group = bool(self.custom_group_combo.get_active_id())
        self.rename_custom_group_button.set_sensitive(has_group)
        self.remove_custom_group_button.set_sensitive(has_group)

    def _custom_group_changed(self, combo):
        self._update_custom_group_buttons()
        if self.updating_controls or self.selected_index < 0:
            return
        self.layouts[self.selected_index]["group_id"] = combo.get_active_id() or ""
        self._rebuild_list()
        self._set_dirty()

    def _prompt_group_name(self, title, initial=""):
        dialog = Gtk.Dialog(
            title=title,
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
        )
        dialog.add_buttons(
            "Cancel", Gtk.ResponseType.CANCEL,
            "OK", Gtk.ResponseType.OK,
        )
        entry = Gtk.Entry()
        entry.set_text(initial)
        entry.set_activates_default(True)
        content = dialog.get_content_area()
        content.set_border_width(12)
        content.pack_start(Gtk.Label(label="Group name", xalign=0), False, False, 4)
        content.pack_start(entry, False, False, 4)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.show_all()
        response = dialog.run()
        value = entry.get_text().strip() if response == Gtk.ResponseType.OK else ""
        dialog.destroy()
        return value

    def _new_custom_group(self, _button):
        name = self._prompt_group_name("Create Custom Group")
        if not name:
            return
        group_id = f"group-{time.monotonic_ns():x}"
        used_slots = {
            group.get("fillShortcutSlot") for group in self.custom_groups
        }
        fill_shortcut_slot = next(
            (slot for slot in range(1, MAX_LAYOUTS + 1) if slot not in used_slots),
            1,
        )
        self.custom_groups.append({
            "id": group_id,
            "name": name,
            "fillShortcutSlot": fill_shortcut_slot,
        })
        if 0 <= self.selected_index < len(self.layouts):
            self.layouts[self.selected_index]["group_id"] = group_id
        self._rebuild_custom_group_combo()
        self._rebuild_list()
        self._set_dirty()

    def _rename_custom_group(self, _button):
        group_id = self.custom_group_combo.get_active_id()
        if not group_id:
            return
        initial = self.custom_group_combo.get_active_text() or ""
        name = self._prompt_group_name("Rename Custom Group", initial)
        if not name:
            return
        for group in self.custom_groups:
            if group.get("id") == group_id:
                group["name"] = name
                break
        self._rebuild_custom_group_combo()
        self._rebuild_list()
        self._set_dirty()

    def _remove_custom_group(self, _button):
        group_id = self.custom_group_combo.get_active_id()
        if not group_id:
            return
        self.custom_groups = [
            group for group in self.custom_groups if group.get("id") != group_id
        ]
        for layout in self.layouts:
            if layout.get("group_id") == group_id:
                layout["group_id"] = ""
        self._rebuild_custom_group_combo()
        self._rebuild_list()
        self._set_dirty()

    def _row_selected(self, _list_box, row):
        if self.updating_controls:
            return
        self.selected_index = getattr(row, "layout_index", -1) if row is not None else -1
        self._load_selected_controls()

    def _name_changed(self, entry):
        if self.updating_controls or self.selected_index < 0:
            return
        self.layouts[self.selected_index]["name"] = entry.get_text()
        row = self._layout_rows.get(self.selected_index)
        if row is not None:
            row.get_child().set_text(self._display_name(self.selected_index))
        self._set_dirty()

    def _grid_changed(self, column, row, column_span, row_span):
        if self.updating_controls or self.selected_index < 0:
            return
        self.layouts[self.selected_index].update({
            "column": column,
            "row": row,
            "column_span": column_span,
            "row_span": row_span,
        })
        self._update_geometry_label()
        self._set_dirty()

    def _feature_changed(self, _control, _parameter=None):
        self._update_feature_sensitivity()
        if not self.updating_controls:
            self._set_dirty()

    @staticmethod
    def _validated_group_order(candidate):
        if not isinstance(candidate, (list, tuple)):
            candidate = []
        order = []
        for group_id in candidate:
            if group_id in DEFAULT_GROUP_ORDER and group_id not in order:
                order.append(group_id)
        if "fillDisplay" not in order:
            insert_at = order.index("window") if "window" in order else len(order)
            order.insert(insert_at, "fillDisplay")
        order.extend(group_id for group_id in DEFAULT_GROUP_ORDER if group_id not in order)
        return order

    def _rebuild_group_list(self):
        self.updating_controls = True
        for row in self.group_order_list.get_children():
            self.group_order_list.remove(row)
        rows = []
        for group_id in self.group_order:
            row = Gtk.ListBoxRow()
            row.add(Gtk.Label(label=GROUP_LABELS[group_id], xalign=0))
            self.group_order_list.add(row)
            rows.append(row)
        self.group_order_list.show_all()
        if rows:
            self.selected_group_index = max(
                0,
                min(self.selected_group_index, len(rows) - 1),
            )
            self.group_order_list.select_row(rows[self.selected_group_index])
        self.updating_controls = False
        self._update_group_buttons()

    def _group_row_selected(self, _list_box, row):
        if self.updating_controls:
            return
        self.selected_group_index = row.get_index() if row is not None else -1
        self._update_group_buttons()

    def _update_group_buttons(self):
        valid = 0 <= self.selected_group_index < len(self.group_order)
        self.group_up_button.set_sensitive(valid and self.selected_group_index > 0)
        self.group_down_button.set_sensitive(
            valid and self.selected_group_index < len(self.group_order) - 1
        )

    def _move_group_up(self, _button):
        self._move_group(-1)

    def _move_group_down(self, _button):
        self._move_group(1)

    def _move_group(self, offset):
        target = self.selected_group_index + offset
        if not 0 <= self.selected_group_index < len(self.group_order):
            return
        if not 0 <= target < len(self.group_order):
            return
        group_id = self.group_order.pop(self.selected_group_index)
        self.group_order.insert(target, group_id)
        self.selected_group_index = target
        self._rebuild_group_list()
        self._set_dirty()

    def _update_feature_sensitivity(self):
        self.floating_button_size_combo.set_sensitive(
            self.floating_button_switch.get_active()
        )
        drag_targets_enabled = self.drag_targets_switch.get_active()
        self.zone_targets_radio.set_sensitive(drag_targets_enabled)
        self.top_targets_radio.set_sensitive(drag_targets_enabled)
        self.show_all_zone_targets_switch.set_sensitive(
            drag_targets_enabled and self.zone_targets_radio.get_active()
        )
        self.show_all_top_targets_switch.set_sensitive(
            drag_targets_enabled and self.top_targets_radio.get_active()
        )

    @staticmethod
    def _percent(value, total):
        return int((value * 100 / total) + 0.5)

    def _update_geometry_label(self):
        if not (0 <= self.selected_index < len(self.layouts)):
            self.geometry_label.set_text("No layout selected")
            return

        layout = self.layouts[self.selected_index]
        x = self._percent(layout["column"], GRID_COLUMNS)
        y = self._percent(layout["row"], GRID_ROWS)
        width = self._percent(layout["column_span"], GRID_COLUMNS)
        height = self._percent(layout["row_span"], GRID_ROWS)
        self.geometry_label.set_text(
            f"Position: {x}%, {y}% · Size: {width}% × {height}%"
        )

    def _add_layout(self, _button):
        if len(self.layouts) >= MAX_LAYOUTS:
            return
        used_slots = {layout.get("shortcut_slot") for layout in self.layouts}
        shortcut_slot = next(
            (slot for slot in range(1, MAX_LAYOUTS + 1) if slot not in used_slots),
            1,
        )
        self.layouts.append({
            "name": f"Custom Layout {len(self.layouts) + 1}",
            "column": 0,
            "row": 0,
            "column_span": GRID_COLUMNS // 2,
            "row_span": GRID_ROWS // 2,
            "shortcut_slot": shortcut_slot,
            "group_id": "",
        })
        self.selected_index = len(self.layouts) - 1
        self._rebuild_list()
        self._set_dirty()

    def _remove_layout(self, _button):
        if self.selected_index < 0:
            return
        removed_index = self.selected_index
        self.layouts.pop(removed_index)
        self.selected_index = min(removed_index, len(self.layouts) - 1)
        self._rebuild_list()
        self._set_dirty()

    def _move_up(self, _button):
        self._move_selected(-1)

    def _move_down(self, _button):
        self._move_selected(1)

    def _move_selected(self, offset):
        target = self._adjacent_layout_index(offset)
        if target < 0:
            return
        layout = self.layouts.pop(self.selected_index)
        self.layouts.insert(target, layout)
        self.selected_index = target
        self._rebuild_list()
        self._set_dirty()

    def _apply(self, _button):
        serialized = []
        for index, layout in enumerate(self.layouts):
            serialized.append({
                "name": layout["name"].strip() or f"Custom Layout {index + 1}",
                "x": round(layout["column"] / GRID_COLUMNS, 6),
                "y": round(layout["row"] / GRID_ROWS, 6),
                "width": round(layout["column_span"] / GRID_COLUMNS, 6),
                "height": round(layout["row_span"] / GRID_ROWS, 6),
                "shortcutSlot": layout.get("shortcut_slot", index + 1),
                "groupId": layout.get("group_id", ""),
            })
        try:
            self.save_callback(serialized)
            self.save_groups_callback(self.custom_groups)
            self.save_settings_callback({
                "floating_button_enabled": self.floating_button_switch.get_active(),
                "drag_targets_enabled": self.drag_targets_switch.get_active(),
                "drag_target_placement": (
                    "top" if self.top_targets_radio.get_active() else "zones"
                ),
                "show_all_drag_targets": (
                    self.show_all_zone_targets_switch.get_active()
                ),
                "show_all_top_drag_targets": (
                    self.show_all_top_targets_switch.get_active()
                ),
                "floating_button_size": (
                    self.floating_button_size_combo.get_active_id() or "default"
                ),
                "layout_padding": self.layout_padding_spin.get_value_as_int(),
                "group_order": list(self.group_order),
            })
        except Exception as error:  # keep the editor open and show a useful error
            self.status_label.set_text(f"Could not save changes: {error}")
            return False
        self._set_dirty(False)
        self.status_label.set_text("Changes applied.")
        return True

    def _ok(self, button):
        if self._apply(button):
            self.hide()
