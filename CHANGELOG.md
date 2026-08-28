# Changelog

All notable changes to Window Layouts are documented here. This project uses
[Semantic Versioning](https://semver.org/).

## [1.3.1] - 2026-08-28

### Fixed

- Plasma now refreshes briefly after a version-changing upgrade so its native
  About page reloads the installed Plasmoid metadata instead of showing the
  version cached by the previous widget instance.
- Runtime package cache-busters now derive their version from the canonical
  `VERSION` file rather than another manually maintained version string.

### Changed

- Release-archive generation now refuses to proceed unless every component and
  About metadata version matches the canonical `VERSION` file.

## [1.3.0] - 2026-08-28

### Added

- Portable JSON import and export for all custom layouts and named custom
  groups from both the Plasma configuration page and the shared configurator
  opened through Cairo-Dock or the floating button.
- Compatibility with the Window Layouts for macOS v1.3.0 archive schema, plus
  optional KDE shortcut-slot metadata for lossless KDE-to-KDE transfers.
- Regression coverage for archive round trips, macOS-format imports, malformed
  identifiers, invalid geometry, missing group references, limits, and both
  configuration frontends.

### Behavior

- Import replaces only the draft custom layouts and groups after confirmation.
  Feature settings, padding, menu-group order, and other preferences remain
  unchanged, and **Cancel** discards an unapplied import.
- Imported archives are size-limited and fully validated before use. Exports
  are written atomically so an interrupted write cannot leave a partial file.

## [1.2.1] - 2026-08-26

### Changed

- The Plasma and shared GTK About pages now show the project slogan above the
  KDE Plasma Wayland description.
- An optional, reversible Xwayland Video Bridge compatibility helper can
  disable its user-session autostart when a transparent capture window blocks
  desktop input. Window Layouts never applies this workaround automatically.

### Fixed

- The panel's Updates page now opens its own content instead of leaving the
  previously selected configuration page visible.
- The update confirmation dialog no longer assigns a read-only Qt 6 QML
  `implicitWidth` property.

## [1.2.0] - 2026-08-26

### Added

- A GitHub release checker in the panel configuration and the shared GTK
  configurator opened from Cairo-Dock or the floating button.
- User-confirmed installation of release archives after verifying their
  published SHA-256 checksum. Updates preserve existing Window Layouts
  configuration and do not require administrator privileges.
- Offline updater regression coverage for semantic-version comparison, release
  asset selection, and archive path-traversal rejection.

### Changed

- About information now identifies Dr. Bret Addison as the author and links
  the project website and help actions to the Window Layouts GitHub repository.
- The native Plasma About page uses the Window Layouts logo. Plasma's adjacent
  Updates page and the shared GTK About & Updates dialog use the same branding
  and release source.

### Fixed

- The drag-target Wayland surface is now forced transparent and off-screen at
  1 × 1 unless KWin still reports a genuine interactive move. Its input-mask
  workaround and per-drag surface creation were removed to avoid compositor
  churn while retaining a geometry-based pointer-input fail-safe.
- The shared configurator now detects and removes only abandoned KConfig lock
  files. A timed-out `kwriteconfig6` process can therefore no longer leave all
  later Apply attempts waiting on a dead process.

## [1.1.0] - 2026-08-24

### Added

- Fill Display actions for Horizontal Halves, Vertical Halves, Quarters, and
  Thirds, plus every non-empty named custom-layout group.
- Fill Display entries in the panel menu, floating-button menu, KWin window
  actions menu, and optional Cairo-Dock sub-dock.
- Global keyboard shortcuts for every built-in Fill Display action and each
  named custom group, using stable custom-group shortcut slots.
- Automated KWin fill regression coverage for window eligibility, front-to-back
  assignment, layout wrapping, custom groups, and Restore.

### Changed

- Menu group ordering now includes a separately reorderable Fill Display group.
- Cairo-Dock uses compact `Fill: …` labels and combined SVG previews for
  multi-window fill actions.
- Panel and floating-button Fill Display entries use combined miniatures that
  show every layout region in the selected group.
- Custom-group records now retain a stable `fillShortcutSlot` when a group is
  renamed or reordered.

### Behavior

- Fill Display targets the focused window's display and current desktop and
  activity. It includes eligible visible normal windows in front-to-back order,
  excludes minimized, full-screen, special, immovable, and non-resizable
  windows, and wraps through the selected layouts when necessary.
- Every moved window keeps its own Restore geometry. Normalized layouts and
  existing padding rules are calculated against the target display's usable
  area, including mixed-resolution and scaled monitor configurations.

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
