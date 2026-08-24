# Window Layouts for KDE Plasma

Window Layouts is a window-positioning and tiling utility inspired by Magnet
for **KDE Plasma 6 on Wayland**. It provides named layouts for the focused
window, including familiar halves, quarters, and thirds, together with up to 20
custom layouts that adapt to each monitor's usable area.

The project is designed for a native Wayland Plasma session: KWin moves the
application window itself, so it does not inject buttons into application title
bars or rely on X11 window-management tools.

## Features

- Fixed halves, quarters, thirds, two-thirds, maximize, center, and restore
  layouts.
- Up to 20 named custom layouts, selected on a 24 × 12 visual grid.
- Named custom-layout groups for organizing related layouts.
- Fill the focused display with eligible visible windows using Horizontal
  Halves, Vertical Halves, Quarters, Thirds, or any non-empty named custom
  group. Windows are assigned front-to-back and layouts wrap when needed.
- A panel widget, a floating button beside the focused window, and an optional
  Cairo-Dock sub-dock that all invoke the same KWin actions.
- Move the focused window to the next or previous monitor and workspace, with
  wrap-around. Cross-monitor moves preserve proportional placement and rescale
  the window for different resolutions, display scaling, panels, and usable
  areas. Commands are unavailable when there is nowhere to move.
- Optional layout padding from 0 to 200 pixels. Monitor-edge layout boundaries
  remain flush while internal edges are inset by the chosen amount.
- Optional on-screen layout targets while dragging a window. Targets can appear
  at the center of matching layout zones or together in a top-center strip,
  with proximity-based or immediate display for either mode.
- Global keyboard shortcuts for every layout and for previous/next workspace
  and monitor movement, with KDE conflict detection and an explicit warning
  before an existing shortcut is reassigned.
- Named groups within the custom layouts, useful for keeping related layouts
  together without changing their geometry.
- Reorder menu groups: Halves, Quarters, Thirds, Two Thirds, Custom, Fill
  Display, and Window.
- Per-window Restore geometry, so a laid-out window can return to its previous
  size and position.
- Settings shared between the panel, floating button, Cairo-Dock, and the
  configuration windows.

Version **1.1.0** adds multi-window Fill Display actions across every frontend
and the global-shortcut editors.

## Screenshots

The sample custom-layout names shown below are illustrative only. A fresh
installation starts with an empty custom-layout list, ready for your own
layouts.

### Panel widget

<p align="center">
  <a href="screenshots/readme/panel-menu.png"><img src="screenshots/readme/panel-menu.png" alt="Window Layouts panel menu with custom layouts and fixed layout groups" width="720"></a>
</p>

### Floating button

<p align="center">
  <a href="screenshots/readme/floating-button.png"><img src="screenshots/readme/floating-button.png" alt="Floating Window Layouts button beside a focused window" width="36%"></a>
  <a href="screenshots/readme/floating-button-menu.png"><img src="screenshots/readme/floating-button-menu.png" alt="Floating Window Layouts button menu with layout previews" width="39%"></a>
</p>

### Custom-layout configuration

<p align="center">
  <a href="screenshots/readme/configuration.png"><img src="screenshots/readme/configuration.png" alt="Configure Window Layouts window, including the 24 by 12 grid and feature settings" width="960"></a>
</p>

### Optional Cairo-Dock integration

<p align="center">
  <a href="screenshots/readme/cairo-dock-subdock.png"><img src="screenshots/readme/cairo-dock-subdock.png" alt="Cairo-Dock Window Layouts sub-dock with visual layout choices" width="650"></a>
</p>

## Requirements

### Core requirements

- Fedora KDE Plasma 44 or another Plasma 6 + KWin 6 Wayland session.
- Python 3, GTK 3, Python GObject bindings, and Python D-Bus bindings for the
  shared configuration window.
- The following commands: `kpackagetool6`, `kreadconfig6`, `kwriteconfig6`,
  `qdbus-qt6`, `qtpaths6`, and `kscreen-doctor`.

Most of these are already installed on Fedora KDE. On Fedora 44, install any
missing core dependencies with:

```bash
sudo dnf install \
  kf6-kpackage kf6-kconfig qt6-qttools qt6-qtbase libkscreen \
  plasma-workspace python3-gobject python3-dbus gtk3
```

### Optional Cairo-Dock requirements

The Cairo-Dock frontend also needs:

```bash
sudo dnf install cairo-dock cairo-dock-plug-ins-dbus cairo-dock-python3
```

## Install

Clone or download this repository, open a terminal in the project directory,
then install the core Window Layouts components into your user account:

```bash
cd window-layouts-kde
./install.sh
./place-on-panel.sh
```

`install.sh` installs the KWin actions, panel widget, floating-button package,
drag-target package, and shared configuration service. The floating button and
drag targets are intentionally disabled on a fresh install; enable them from
the configuration window when you are ready to use them.

`place-on-panel.sh` adds Window Layouts to a Plasma panel on the primary
screen. It removes only existing Window Layouts widgets from desktop
containments, which prevents an accidental desktop widget while leaving all
other widgets untouched.

You can also add the widget manually through **Edit Mode** on a panel → **Add
Widgets** → **Window Layouts**. Adding it from the desktop widget browser adds
it to the desktop instead of a panel.

## Configure Window Layouts

Click the Window Layouts panel icon and choose **Configure…** to open the
configuration window. The same shared configuration window is also available
from the Cairo-Dock applet and the floating-button menu.

Use it to:

1. Add, name, remove, and reorder up to 20 custom layouts.
2. Drag across the 24 × 12 grid to set a custom layout's proportional position
   and size.
3. Create, rename, and remove named custom groups, then assign custom layouts
   to them. The Saved layouts list displays group headings and keeps
   unassigned layouts together.
4. Reorder the built-in layout and action groups shown by the menus.
5. Enable or disable the floating button and on-screen drag targets.
6. Choose whether drag targets appear at their matching layout zones or in a
   top-center strip, and whether the selected target style appears immediately.
7. Choose the floating-button size: Small, Default, Big, or Extra big.
8. Set optional layout padding in pixels. Padding is applied only to layout
   edges that do not touch the monitor's usable boundary.
9. Assign or remove a global shortcut for every fixed and custom layout, every
   built-in or custom-group Fill Display action, or moving a window to the
   previous/next workspace or monitor, from **Layout Shortcuts**. KDE
   identifies conflicts and asks before reassigning a shortcut owned by
   another action.

Choose **Apply** to save changes and keep editing, **OK** to save changes and
close the configuration window, or **Cancel** to discard unapplied changes.
Custom layouts are proportional to each display's usable area, so they remain
useful across different resolutions, scaling factors, and panel configurations.

## Using Window Layouts

### Panel widget

Click the panel icon, then choose a layout for the focused application window.
The menu also provides Restore, workspace movement, monitor movement, and
Configure options. Monitor and workspace movement wraps at each end of the
available list. Monitor movement preserves the window's normalized layout or
free-form geometry, so it scales to the destination display's resolution,
scaling factor, and usable area.

### Fill Display

Open the **Fill Display** menu group and choose Horizontal Halves, Vertical
Halves, Quarters, Thirds, or a named custom group. The focused window selects
the target display. Window Layouts then arranges eligible visible application
windows on that display in front-to-back order; when there are more windows
than layout slots, it wraps back to the first layout.

Fill Display includes normal movable and resizable windows on the target
display's current desktop and activity. Minimized, full-screen, special,
immovable, and non-resizable windows are left untouched. Every moved window
retains its own Restore geometry, and each layout is calculated against that
display's usable area and scaling. Empty custom groups are omitted from menus.

### Keyboard shortcuts

Open **Configure… → Layout Shortcuts** to assign or remove a global shortcut
for any fixed or custom layout, Fill Display choice, or action that moves the
focused window to the previous or next workspace or monitor. If a proposed
shortcut is already in use, KDE identifies the conflict and Window Layouts asks
for confirmation before reassigning it.

### Floating button

When enabled, the compact blue button follows an eligible focused window near
its upper edge. It moves to the left side when the window is too close to the
right edge of its display. Click it to open the same layout menu used by the
panel.

The floating button is hidden for the desktop, minimized windows, maximized
windows, full-screen windows, and special or non-resizable windows. Its menu
also includes a **Show floating button** switch, so it can be disabled quickly
if needed. Re-enable it through **Configure Window Layouts** from the panel or
Cairo-Dock.

KWin also registers an unassigned shortcut named **Window Layouts: Toggle
Floating Menu**. Assign a key sequence in System Settings if you prefer a
keyboard shortcut.

### On-screen drag layouts

When enabled, start moving a normal window with the mouse. In the default zone
mode, targets appear when the pointer approaches a layout region. In top-center
mode, moving near the top-center trigger reveals a compact strip containing all
layouts. Either mode can instead display its targets immediately. Hovering a
target previews the destination; release the mouse over it to apply that
layout.

### Cairo-Dock frontend

Install the optional Cairo-Dock integration with:

```bash
./install-cairo-dock.sh
```

Then enable **Window Layouts** in **Cairo-Dock Configuration → Add-ons**. The
applet opens a sub-dock with layout previews and the same window actions.
Multi-window choices use compact **Fill: …** labels and combined previews. It
refreshes when monitors or workspaces change, and monitor entries are visibly
unavailable when only one monitor is connected.

The installer adds a small user-session guard to keep Cairo-Dock on KDE's
primary output after display changes and unlocks. It first asks an existing
dock to reveal itself and only restarts Cairo-Dock after an output-topology
change or when the dock is unavailable. It works with Cairo-Dock's existing
autostart service and does not start a duplicate dock.

## Updating and uninstalling

For panel, floating-button, drag-target, shared configurator, or Cairo-Dock
source changes, run:

```bash
./install-drag-overlay.sh
```

This upgrades the core action script and UI packages while preserving custom
layouts, custom groups, shortcuts, floating-button, drag-target, size, target
placement, and group-order settings already selected.

`install.sh` remains the clean first-install path and intentionally resets the
optional floating-button and drag-target settings to their safe defaults.

To remove the core components and panel widget:

```bash
./uninstall.sh
```

The optional Cairo-Dock add-on can be disabled from **Cairo-Dock Configuration
→ Add-ons**. A dedicated Cairo-Dock cleanup script is planned as part of the
packaging work.

## Troubleshooting

If layouts do not move a window, check **System Settings → Window Management →
KWin Scripts** and confirm **Window Layouts** is enabled. Useful logs are:

```bash
journalctl --user -f | grep -E 'window-layouts|windowlayouts'
```

If the optional floating button ever prevents normal input, switch to a virtual
terminal and disable it:

```bash
kwriteconfig6 --file kwinrc --group Plugins \
  --key windowlayoutsfloatingbuttonEnabled --type bool false
qdbus-qt6 org.kde.KWin /Scripting \
  org.kde.kwin.Scripting.unloadScript windowlayoutsfloatingbutton
qdbus-qt6 org.kde.KWin /KWin reconfigure
```

## Support, bugs, and contributions

Please report bugs, feature requests, and reproducible problems through the
[GitHub Issues tracker](../../issues). Include your Plasma/KWin version,
Fedora version, display setup, steps to reproduce the issue, and relevant log
output where possible.

You can also reach the maintainer through the
[baddison2005 GitHub profile](https://github.com/baddison2005).

If Window Layouts has been useful to you, please consider supporting its
development through [GitHub Sponsors](https://github.com/sponsors/baddison2005).
Thank you so much!

## Project internals

For the component map, persisted settings, important functions, and extension
notes, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Release history is recorded in [CHANGELOG.md](CHANGELOG.md). The current
release number is also available in [VERSION](VERSION).

## License

Window Layouts is distributed under **GPL-3.0-or-later**. The QML and
JavaScript files are marked GPL-2.0-or-later, which permits distribution under
GPLv3; the Python components are GPL-3.0-or-later. See the SPDX headers in the
source files for the applicable file-level notices. The complete license text
is available in [LICENSE](LICENSE).
