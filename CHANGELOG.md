# Changelog

All notable changes to Window Layouts are documented here. This project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-08-18

### Added

- A top-center layout-target mode, as an alternative to targets located in the
  center of each layout zone.
- Independent immediate-display preferences for zone-center and top-center
  targets.
- Per-layout global shortcut editors in both configuration interfaces, with
  conflict detection and explicit reassignment confirmation.
- Stable shortcut slots for custom layouts, so shortcuts remain attached when
  layouts are reordered or moved into a custom group.
- Named custom-layout groups with create, rename, remove, and layout-assignment
  controls.
- Global shortcuts for moving the focused window to the previous or next
  workspace or monitor.
- Configurable 0–200 pixel layout padding that keeps usable monitor boundaries
  flush and insets only internal layout edges.
- Version files and component metadata for the 1.0.0 release line.

### Changed

- Custom-layout menus keep named groups together across the panel, floating
  button, Cairo-Dock, drag targets, and KWin window-actions menu.
- Saved-layout editors display custom layouts under group headings, followed
  by an Unassigned section.
- Panel group headings are more prominent, grouped layouts use compact spacing,
  and the create/rename group dialogs provide enough room for their fields.
- Panel configuration writes are bundled and validated to avoid partial
  layout/group synchronization during Plasma startup or Apply.
- The Cairo-Dock session guard backs off when KScreen is unavailable and
  reveals a responsive dock after unlock instead of restarting it.
- Cairo-Dock capability refreshes reuse one display/workspace query, retain
  the last known state across transient failures, and run less frequently.
- Cairo-Dock also detects custom-layout and custom-group changes made in the
  panel or shared configurator and refreshes its sub-dock automatically; panel
  saves also request an immediate refresh from a running applet.
- Cairo-Dock custom entries use the concise layout name without a custom-group
  prefix; group labels remain available in the panel and floating-button menus.
- Previous/next monitor actions preserve recognized layouts or normalized
  free-form geometry and rescale windows for the destination monitor's usable
  area, resolution, and display scaling.
- Idle KWin polling for drag detection is reduced while retaining a fallback
  for missed compositor signals.
- The development updater now upgrades and reloads the core action script while
  preserving optional-feature settings.

## [0.5.1] - 2026-08-07

- Initial public release of the panel widget, KWin actions, floating button,
  drag targets, shared configurator, and optional Cairo-Dock frontend.
