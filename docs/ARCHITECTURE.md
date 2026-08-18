# Window Layouts architecture guide

This document is for maintainers and contributors. It explains the runtime
components, how settings move between them, and the files that should be
updated together when adding a feature.

## Design overview

Window Layouts has one authority for moving windows: the JavaScript KWin action
script. Every user interface sends a named KWin action to that script instead
of changing a window directly.

```text
Panel widget ───────┐
Floating button ────┼──> org.kde.kglobalaccel ──> KWin action script ──> window geometry
Cairo-Dock applet ─┘

Panel / Cairo-Dock / floating Configure
                    └──> shared D-Bus configurator ──> kwinrc + panel config
                                                      └──> KWin reconfigure
```

This separation is intentional. UI surfaces can be replaced or disabled while
the actions and saved layouts remain available through KWin's window operations
menu.

## Runtime components

| Component | Language | Role |
| --- | --- | --- |
| `packages/kwin-script` | JavaScript | Registers global actions and changes window geometry. |
| `packages/plasmoid` | QML + shell helpers | Panel widget, panel configuration page, and settings forwarding. |
| `packages/floating-button` | QML | Wayland-native compact button and popup beside the focused window. |
| `packages/drag-overlay` | QML | Input-transparent layout targets displayed during an interactive move. |
| `helpers/window-layouts-configurator-service` | Python | D-Bus host and canonical settings synchronizer. |
| `cairo-dock-applet/window-layouts` | Python | Cairo-Dock sub-dock frontend and GTK configuration entry point. |
| `cairo-dock-applet/window-layouts/configurator.py` | Python + GTK 3 | Shared layout, custom-group, shortcut, feature, and group-order editor. |

## Settings and ownership

The user configuration is stored in `kwinrc`. `LayoutStorage` in
`helpers/window-layouts-configurator-service` validates and synchronizes it.

| Setting | Canonical KWin group/key | Mirrored to |
| --- | --- | --- |
| Custom layouts | `Script-windowlayouts/CustomLayouts` | Floating button, drag targets, panel config |
| Custom groups | `Script-windowlayouts/CustomGroups` | Floating button, drag targets, panel config |
| Group order | `Script-windowlayouts/GroupOrder` | Floating button, drag targets, panel config |
| Floating button enabled | `Plugins/windowlayoutsfloatingbuttonEnabled` | Panel config |
| Drag targets enabled | `Plugins/windowlayoutsdragtargetsEnabled` | Panel config |
| Show all drag targets | `Script-windowlayoutsdragtargets/ShowAllTargets` | Panel config |
| Drag-target placement | `Script-windowlayoutsdragtargets/TargetPlacement` | Panel config |
| Show all top targets | `Script-windowlayoutsdragtargets/ShowAllTopTargets` | Panel config |
| Floating button size | `Script-windowlayoutsfloatingbutton/ButtonSize` | Panel config |
| Layout padding | `Script-windowlayouts/LayoutPadding` | Drag-target preview, panel config |

Global shortcuts are owned by KDE's `org.kde.kglobalaccel` service rather than
`kwinrc`. Fixed layouts use stable action IDs. Each custom-layout record stores
a stable `shortcutSlot` from 1 through 20 and resolves to
`WindowLayoutsCustom<slot>`, so reordering a layout does not transfer its
shortcut to a different layout. An optional `groupId` references a record in
`CustomGroups`; an empty ID means unassigned. The same shortcut service also
owns the fixed previous/next workspace and monitor movement actions.

The panel stores its own copies in the Plasmoid's `General` configuration group.
That copy lets its KCM configuration page bind normally to `cfg_*` properties.
The D-Bus service writes both the KWin and panel copies whenever a shared GTK
configuration window applies changes.

## Important flows

### Apply a layout

1. A frontend selects an action ID such as `WindowLayoutsLeftHalf`.
2. The frontend invokes `org.kde.kglobalaccel.Component.invokeShortcut` on the
   KWin component.
3. `packages/kwin-script/contents/code/main.js` resolves an eligible target
   window, calculates a rectangle relative to KWin's `MaximizeArea`, applies
   edge-aware padding, and sets `frameGeometry`.
4. Before the first layout operation, the action script stores the original
   geometry for Restore.

`MaximizeArea` is important: it excludes Plasma panels and other reserved
screen edges, so a layout does not end up under a panel.

Layout rectangles use normalized coordinates until the final geometry is
calculated. This allows the same fixed or custom layout to scale across
monitors with different resolutions, scale factors, and reserved panel areas.
Padding is edge-aware: only boundaries inside the usable monitor area are
inset, while boundaries coinciding with a usable screen edge remain flush.

### Apply configuration from the panel

1. The panel KCM writes `cfg_*` values to its Plasmoid configuration after
   **Apply** or **OK**.
2. `packages/plasmoid/contents/ui/main.qml` observes changes and debounces the
   update through `contents/tools/sync-settings.sh` or `sync-layouts.sh`.
3. `sync-layouts.sh` writes committed custom-layout and custom-group JSON
   directly to the three KWin script groups. `sync-settings.sh` calls the
   shared D-Bus configurator service for feature settings and group order.
4. `LayoutStorage.save_feature_settings()` validates feature values, writes
   KWin configuration, mirrors panel values, and calls KWin reconfigure.

The debounce avoids sending several incomplete settings updates while a KCM is
committing related values.

### Apply configuration from Cairo-Dock or the floating menu

1. The GTK `WindowLayoutsConfigurator` calls its supplied save callbacks.
2. Cairo-Dock forwards feature settings to the shared D-Bus service; the
   service's own window writes settings directly through `LayoutStorage`.
3. The service mirrors settings back to the panel and reconfigures KWin.
4. Layout saves from the panel or shared service ask a running Cairo-Dock
   applet to reload immediately. Cairo-Dock's periodic capability refresh is
   the fallback for changed custom layouts, custom-group assignments, or group
   order from any frontend.

### Floating button on Wayland

`FloatingButton.qml` owns a `PlasmaCore.Dialog` rather than an application
title-bar button. The dialog is unmapped and remapped when its target changes,
which avoids Wayland output/position glitches. It accepts input only inside its
actual compact-button or popup geometry; it must never use a monitor-sized
input surface.

### Drag targets

`DragTargetController.qml` monitors KWin's interactive move state. Its overlay
uses `Qt.WindowTransparentForInput`, derives hover from `Workspace.cursorPos`,
and invokes the normal KWin action only after the move completes. This keeps
the overlay from stealing the mouse event that is moving the application
window.

## File and function reference

### KWin action script

`packages/kwin-script/contents/code/main.js`

- `targetWindow()` chooses the active or most recently eligible normal window.
- `rememberOriginalGeometry()` and `restoreWindow()` implement Restore.
- `rectangleForLayout()` converts normalized layout fractions into pixel
  geometry in the window's current `MaximizeArea` and insets only internal
  layout edges by the configured padding.
- `normalizedGeometry()` and `matchingLayout()` let monitor movement preserve
  either a recognized layout or proportional free-form geometry across
  different usable monitor sizes.
- `applyLayout()`, `maximizeWindow()`, and `centerWindow()` perform geometry
  changes.
- `moveToAdjacentMonitor()` implements wrapped, resolution-aware monitor
  movement; `moveToAdjacentWorkspace()` implements wrapped workspace movement.
- `loadCustomLayouts()` validates the persisted custom-layout JSON.
- `loadConfiguration()` reloads custom layouts, custom groups, group order,
  and padding when KWin reconfigures the script.
- `openConfigurator()` requests `Show()` on the shared D-Bus service.

The fixed action IDs are consumed by every frontend. When adding a fixed
layout, update this script, the panel model, floating-button model,
drag-target model, and Cairo-Dock `FIXED_LAYOUTS` together.

### Shared configuration service

`helpers/window-layouts-configurator-service`

- `LayoutStorage.load()` / `save()` manage custom-layout JSON.
- `load_feature_settings()` / `save_feature_settings()` manage feature flags,
  size, padding, and group order.
- `_set_script_enabled()` explicitly loads or unloads optional declarative
  scripts. Reconfigure alone does not reliably unload a script that was loaded
  manually in the current session.
- `SetFloatingButtonEnabled()` lets the floating button disable itself safely.
- `SetFeatureSettingsV3()` is the current multi-setting D-Bus synchronization
  endpoint. V1 and V2 remain available for older installed frontends and
  preserve the current padding when they save their older setting set.
- `ShortcutStorage` reads, checks, assigns, and clears KGlobalAccel actions.
  Conflict reassignment removes only the chosen key from previous actions.
- `GetShortcutsJson()` / `SetShortcutText()` support the Plasma shortcut page;
  the GTK editor uses the same `ShortcutStorage` methods directly.

`helpers/org.example.WindowLayouts.Configurator.service.in` makes the Python
service D-Bus activatable in the user session.

### Panel widget

`packages/plasmoid/contents/ui/main.qml`

- `rebuildMenu()` creates all fixed, custom, and Window entries.
- `parsedGroupOrder()` and `reorderMenuGroups()` arrange those entries without
  changing their stable action IDs.
- `syncCustomLayouts()` and `syncFeatureSettings()` forward panel KCM changes.
- `refreshCapabilities()` queries monitor and workspace counts to disable
  inappropriate actions.

`packages/plasmoid/contents/ui/config/ConfigLayouts.qml` is the Plasma KCM
page. It has independent models for custom layouts, the grouped Saved layouts
view, custom groups, and the six menu groups; the `store*()` functions only
update `cfg_*` properties so Cancel remains safe.

`ConfigShortcuts.qml` uses KDE's native `KeySequenceItem`, whose validator
checks global and standard shortcut conflicts. Accepted changes are sent
through `sync-shortcuts.sh` to the shared service.

Custom shortcuts attach to stable numbered slots rather than list positions.
Moving a custom layout within the Saved layouts list or assigning it to a
different custom group therefore does not move its shortcut to another layout.

### Floating button and drag overlay

`packages/floating-button/contents/ui/components/FloatingButton.qml`

- Maintains the eligible focused window and calculates compact/popup position.
- Reads `ButtonSize` and `GroupOrder` from KWin configuration.
- Builds the same grouped menu as the panel, then invokes KWin actions.

`packages/drag-overlay/contents/ui/DragTargetController.qml`

- `allLayouts()` reads custom layouts and group order.
- `rebuildTargets()` places cards at normalized layout centers or builds the
  top-center strip, depending on `TargetPlacement`.
- `updateHover()` reveals the selected target style, calculates preview
  geometry, and identifies the action to apply.
- `finishDrag()` waits until the interactive move ends before invoking an
  action.

Group order also determines the order of cards stacked at identical centers.

### Cairo-Dock

`cairo-dock-applet/window-layouts/window-layouts`

- `refresh_subdock()` builds entries in the configured group order and creates
  SVG previews. Custom entries deliberately show only the layout name because
  Cairo-Dock has limited label space; named group labels remain a panel and
  floating-button presentation feature.
- `_load_group_order()` follows the canonical KWin setting.
- `_save_feature_settings()` delegates to the D-Bus service, then schedules a
  refresh after the asynchronous D-Bus save.
- `_refresh_capabilities_if_changed()` also detects custom-layout,
  custom-group, monitor, workspace, and group-order changes made from another
  frontend. Its slower background poll reuses the loaded values when rebuilding
  the sub-dock and retains the previous monitor/workspace count if a transient
  query fails.

`cairo-dock-applet/cairo-dock-unlock-guard` and the files under
`cairo-dock-applet/systemd` keep the single Cairo-Dock autostart instance on
KDE's primary output after unlocks and display changes. The guard applies a
failure backoff to KScreen probes, skips them while locked, reveals an existing
dock after a normal unlock, and reserves full restarts for topology changes or
an unavailable dock.

## Adding a layout group

1. Choose a stable lowercase ID, for example `sixths`.
2. Add it to every `DEFAULT_GROUP_ORDER` / group-ID list.
3. Add fixed entries to the KWin action script and each frontend model.
4. Add a label to the panel and GTK configurators.
5. Ensure the drag-target model assigns the same `groupId`.
6. Test an existing saved `GroupOrder`; validation must append new groups so
   old user configurations continue to work.

Do not use translated text as a persistent group key. Persisted keys must stay
stable across language changes.

## Testing and diagnostics

Run static checks after source changes:

```bash
bash -n install.sh install-drag-overlay.sh install-cairo-dock.sh
python3 -m py_compile \
  helpers/window-layouts-configurator-service \
  cairo-dock-applet/window-layouts/configurator.py \
  cairo-dock-applet/window-layouts/window-layouts
xmllint --noout packages/*/contents/config/main.xml
jq empty packages/*/metadata.json
```

Use `./install-drag-overlay.sh` for panel, floating-button, drag-target,
configurator, and Cairo-Dock updates. Use `./install.sh` after changing the
core JavaScript KWin action script; it intentionally initializes optional
features to disabled. For live KWin diagnostics, use:

```bash
journalctl --user -f | grep -E 'window-layouts|windowlayouts'
```

Test at least these cases before release:

- panel, floating-button, and Cairo-Dock layout selection;
- one and two monitor movement, including wrap-around and monitors with
  different resolutions or scale factors;
- one and multiple virtual desktops, including wrap-around;
- custom layout creation, reordering, removal, grouping, and Restore;
- custom-group creation, rename, removal, assignment, and Unassigned display;
- fixed and custom shortcuts, clearing shortcuts, and accepting or rejecting a
  detected conflict;
- previous/next workspace and monitor shortcuts;
- padding at zero and a non-zero value, including layouts that touch usable
  monitor edges;
- floating-button enable/disable and every size;
- zone-center and top-center drag targets in proximity and immediate modes;
- group order changed from both panel and GTK configurators;
- settings synchronized among the panel, floating button, drag targets, and
  Cairo-Dock without restarting the session;
- lock/unlock and monitor disconnect/reconnect when Cairo-Dock is enabled.
