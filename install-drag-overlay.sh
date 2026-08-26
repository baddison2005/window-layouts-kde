#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

# Installs the optional Window Layouts UI features and their shared settings.
# Existing enabled/disabled states are preserved.

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_directory="$project_directory/packages/drag-overlay"
core_package_directory="$project_directory/packages/kwin-script"
floating_package_directory="$project_directory/packages/floating-button"
plasmoid_directory="$project_directory/packages/plasmoid"
configurator_source="$project_directory/helpers/window-layouts-configurator-service"
configurator_ui_source="$project_directory/cairo-dock-applet/window-layouts/configurator.py"
updater_source="$project_directory/helpers/updater.py"
version_source="$project_directory/VERSION"
logo_source="$project_directory/packages/plasmoid/contents/images/window-layouts.svg"
guard_source="$project_directory/cairo-dock-applet/cairo-dock-unlock-guard"
package_id="windowlayoutsdragtargets"
core_package_id="windowlayouts"
legacy_package_id="windowlayoutsdragoverlay"
runtime_cachebuster=$(date +%s%N)
runtime_version="1.2.0-$runtime_cachebuster"
floating_package_id="windowlayoutsfloatingbutton"
floating_runtime_version="1.2.0-$runtime_cachebuster"
data_directory=$(qtpaths6 --writable-path GenericDataLocation)
config_directory=$(qtpaths6 --writable-path ConfigLocation)

read_plugin_state() {
    key=$1
    default_value=$2
    value=$(kreadconfig6 \
        --file kwinrc \
        --group Plugins \
        --key "$key" \
        --default "$default_value")
    case "$value" in
        true|1|yes|on) printf '%s' true ;;
        *) printf '%s' false ;;
    esac
}

floating_enabled=$(read_plugin_state windowlayoutsfloatingbuttonEnabled true)
drag_targets_enabled=$(read_plugin_state windowlayoutsdragtargetsEnabled true)
show_all_drag_targets=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key ShowAllTargets \
    --default false)
case "$show_all_drag_targets" in
    true|1|yes|on) show_all_drag_targets=true ;;
    *) show_all_drag_targets=false ;;
esac
drag_target_placement=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key TargetPlacement \
    --default zones)
case "$drag_target_placement" in
    zones|top) ;;
    *) drag_target_placement=zones ;;
esac
show_all_top_drag_targets=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key ShowAllTopTargets \
    --default false)
case "$show_all_top_drag_targets" in
    true|1|yes|on) show_all_top_drag_targets=true ;;
    *) show_all_top_drag_targets=false ;;
esac
floating_button_size=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsfloatingbutton \
    --key ButtonSize \
    --default default)
case "$floating_button_size" in
    small|default|big|extraBig) ;;
    *) floating_button_size=default ;;
esac
layout_padding=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key LayoutPadding \
    --default 0)
case "$layout_padding" in
    ''|*[!0-9]*) layout_padding=0 ;;
esac
if [ "$layout_padding" -gt 200 ]; then
    layout_padding=200
fi
group_order=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key GroupOrder \
    --default '["halves","quarters","thirds","twoThirds","custom","fillDisplay","window"]')
if ! group_order=$(python3 -c '
import json
import sys

defaults = ["halves", "quarters", "thirds", "twoThirds", "custom", "fillDisplay", "window"]
candidate = json.loads(sys.argv[1])
if not isinstance(candidate, list):
    raise SystemExit(1)

# Repair the short-lived pre-release migration value produced by an earlier
# shell string substitution, then validate and de-duplicate stable group IDs.
expanded = []
for value in candidate:
    if value == "fillDisplay,window":
        expanded.extend(("fillDisplay", "window"))
    else:
        expanded.append(value)
order = []
for value in expanded:
    if value in defaults and value not in order:
        order.append(value)
if "fillDisplay" not in order:
    position = order.index("window") if "window" in order else len(order)
    order.insert(position, "fillDisplay")
for value in defaults:
    if value not in order:
        order.append(value)
print(json.dumps(order, separators=(",", ":")))
' "$group_order")
then
    group_order='["halves","quarters","thirds","twoThirds","custom","fillDisplay","window"]'
fi
group_order_escaped=${group_order//\\/\\\\}
group_order_escaped=${group_order_escaped//\"/\\\"}

# Retire the short-lived first package ID. Using a new package URL also avoids
# KWin's in-session QML component cache after a development upgrade.
kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key "${legacy_package_id}Enabled" \
    --type bool \
    false
if command -v qdbus-qt6 >/dev/null 2>&1; then
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.unloadScript \
        "$legacy_package_id" >/dev/null || true
fi
if kpackagetool6 --type KWin/Script --show "$legacy_package_id" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --remove "$legacy_package_id"
fi

if kpackagetool6 --type KWin/Script --show "$core_package_id" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --upgrade "$core_package_directory"
else
    kpackagetool6 --type KWin/Script --install "$core_package_directory"
fi

if kpackagetool6 --type KWin/Script --show "$package_id" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --upgrade "$package_directory"
else
    kpackagetool6 --type KWin/Script --install "$package_directory"
fi

if kpackagetool6 --type KWin/Script --show "$floating_package_id" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --upgrade "$floating_package_directory"
else
    kpackagetool6 --type KWin/Script --install "$floating_package_directory"
fi

# Install the small synchronization changes in frontends that are already
# present. This does not add widgets, restart Cairo-Dock, or change the state
# of the floating-button KWin script.
if kpackagetool6 --type Plasma/Applet --show org.example.windowlayouts >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$plasmoid_directory"
fi

installed_configurator="$data_directory/window-layouts-kde/configurator/window-layouts-configurator-service"
if [ -f "$installed_configurator" ]; then
    install -m 755 "$configurator_source" "$installed_configurator"
    install -m 644 \
        "$configurator_ui_source" \
        "$(dirname -- "$installed_configurator")/configurator.py"
    install -m 644 \
        "$updater_source" \
        "$(dirname -- "$installed_configurator")/updater.py"
    install -m 644 \
        "$version_source" \
        "$(dirname -- "$installed_configurator")/VERSION"
    install -m 644 \
        "$logo_source" \
        "$(dirname -- "$installed_configurator")/window-layouts.svg"
    if [ "${WINDOW_LAYOUTS_SKIP_CONFIGURATOR_RESTART:-false}" != true ] \
            && command -v qdbus-qt6 >/dev/null 2>&1; then
        qdbus-qt6 \
            org.example.WindowLayouts.Configurator \
            /org/example/WindowLayouts/Configurator \
            org.example.WindowLayouts.Configurator.Quit \
            >/dev/null 2>&1 || true
    fi
fi

installed_cairo_applet="$config_directory/cairo-dock/third-party/window_layouts/window_layouts"
if [ -f "$installed_cairo_applet" ]; then
    install -m 755 \
        "$project_directory/cairo-dock-applet/window-layouts/window-layouts" \
        "$installed_cairo_applet"
    install -m 644 \
        "$configurator_ui_source" \
        "$(dirname -- "$installed_cairo_applet")/configurator.py"
    install -m 644 \
        "$project_directory/cairo-dock-applet/window-layouts/auto-load.conf" \
        "$(dirname -- "$installed_cairo_applet")/auto-load.conf"
fi

installed_guard="$data_directory/window-layouts-kde/cairo-dock-unlock-guard"
if [ -f "$installed_guard" ]; then
    install -m 755 "$guard_source" "$installed_guard"
    # Reload only the lightweight guard. It no longer restarts Cairo-Dock for
    # an ordinary unlock, so applying an update does not exercise Cairo-Dock's
    # fragile plug-in shutdown path.
    if systemctl --user is-enabled --quiet cairo-dock-unlock-guard.service; then
        systemctl --user restart cairo-dock-unlock-guard.service
    fi
fi

custom_layouts=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key CustomLayouts \
    --default '[]')
custom_layouts_escaped=${custom_layouts//\\/\\\\}
custom_layouts_escaped=${custom_layouts_escaped//\"/\\\"}
custom_groups=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key CustomGroups \
    --default '[]')
if ! custom_groups=$(python3 -c '
import json
import sys

candidate = json.loads(sys.argv[1])
if not isinstance(candidate, list):
    raise SystemExit(1)
groups = []
used_ids = set()
used_slots = set()
for group in candidate[:20]:
    if not isinstance(group, dict):
        continue
    group_id = group.get("id")
    name = group.get("name")
    if (not isinstance(group_id, str) or not group_id or group_id in used_ids
            or not isinstance(name, str) or not name.strip()):
        continue
    slot = group.get("fillShortcutSlot")
    if (isinstance(slot, bool) or not isinstance(slot, int)
            or not 1 <= slot <= 20 or slot in used_slots):
        slot = next(value for value in range(1, 21) if value not in used_slots)
    groups.append({"id": group_id, "name": name.strip(), "fillShortcutSlot": slot})
    used_ids.add(group_id)
    used_slots.add(slot)
print(json.dumps(groups, separators=(",", ":"), ensure_ascii=False))
' "$custom_groups")
then
    custom_groups='[]'
fi
custom_groups_escaped=${custom_groups//\\/\\\\}
custom_groups_escaped=${custom_groups_escaped//\"/\\\"}
kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key CustomLayouts \
    "$custom_layouts"
kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsfloatingbutton \
    --key CustomLayouts \
    "$custom_layouts"

for group in \
    Script-windowlayouts \
    Script-windowlayoutsfloatingbutton \
    Script-windowlayoutsdragtargets
do
    kwriteconfig6 \
        --file kwinrc \
        --group "$group" \
        --key CustomGroups \
        "$custom_groups"
done

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsdragtargetsEnabled \
    --type bool \
    "$drag_targets_enabled"

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsfloatingbuttonEnabled \
    --type bool \
    "$floating_enabled"

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key ShowAllTargets \
    --type bool \
    "$show_all_drag_targets"

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key TargetPlacement \
    "$drag_target_placement"

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key ShowAllTopTargets \
    --type bool \
    "$show_all_top_drag_targets"

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsfloatingbutton \
    --key ButtonSize \
    "$floating_button_size"

for group in Script-windowlayouts Script-windowlayoutsdragtargets
do
    kwriteconfig6 \
        --file kwinrc \
        --group "$group" \
        --key LayoutPadding \
        --type int \
        "$layout_padding"
done

for group in \
    Script-windowlayouts \
    Script-windowlayoutsfloatingbutton \
    Script-windowlayoutsdragtargets
do
    kwriteconfig6 \
        --file kwinrc \
        --group "$group" \
        --key GroupOrder \
        "$group_order"
done

if command -v qdbus-qt6 >/dev/null 2>&1; then
    settings_script="var updated = false;
for (var panelIndex = 0; panelIndex < panelIds.length && !updated; panelIndex++) {
    var panel = panelById(panelIds[panelIndex]);
    for (var widgetIndex = 0; widgetIndex < panel.widgetIds.length; widgetIndex++) {
        var widget = panel.widgetById(panel.widgetIds[widgetIndex]);
        if (widget && widget.type === \"org.example.windowlayouts\") {
            widget.currentConfigGroup = [\"General\"];
            widget.writeConfig(\"customLayouts\", \"$custom_layouts_escaped\");
            widget.writeConfig(\"floatingButtonEnabled\", $floating_enabled);
            widget.writeConfig(\"dragTargetsEnabled\", $drag_targets_enabled);
            widget.writeConfig(\"showAllDragTargets\", $show_all_drag_targets);
            widget.writeConfig(\"dragTargetPlacement\", \"$drag_target_placement\");
            widget.writeConfig(\"showAllTopDragTargets\", $show_all_top_drag_targets);
            widget.writeConfig(\"floatingButtonSize\", \"$floating_button_size\");
            widget.writeConfig(\"layoutPadding\", $layout_padding);
            widget.writeConfig(\"groupOrder\", \"$group_order_escaped\");
            widget.writeConfig(\"customGroups\", \"$custom_groups_escaped\");
            updated = true;
            break;
        }
    }
}
print(updated ? \"updated\" : \"missing\");"
    qdbus-qt6 \
        org.kde.plasmashell \
        /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript \
        "$settings_script" >/dev/null || true

    qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null

    installed_core_main="$data_directory/kwin/scripts/$core_package_id/contents/code/main.js"
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.unloadScript \
        "$core_package_id" >/dev/null || true
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.loadScript \
        "$installed_core_main" \
        "$core_package_id" >/dev/null

    # During development, load from a versioned runtime copy after upgrading.
    # The unique URL prevents KWin from reusing a stale QML component cached
    # earlier in the current session. The installed package remains the copy
    # KWin will load automatically at the next login.
    runtime_package="$data_directory/window-layouts-kde/runtime/$package_id-$runtime_version"
    install -d -m 755 \
        "$runtime_package/contents/config" \
        "$runtime_package/contents/ui"
    install -m 644 \
        "$package_directory/metadata.json" \
        "$runtime_package/metadata.json"
    install -m 644 \
        "$package_directory/contents/config/main.xml" \
        "$runtime_package/contents/config/main.xml"
    install -m 644 \
        "$package_directory/contents/ui/main.qml" \
        "$package_directory/contents/ui/DragTargetController.qml" \
        "$runtime_package/contents/ui/"

    if [ "$drag_targets_enabled" = true ]; then
        qdbus-qt6 \
            org.kde.KWin \
            /Scripting \
            org.kde.kwin.Scripting.unloadScript \
            "$package_id" >/dev/null || true
        script_number=$(qdbus-qt6 \
            org.kde.KWin \
            /Scripting \
            org.kde.kwin.Scripting.loadDeclarativeScript \
            "$runtime_package/contents/ui/main.qml" \
            "$package_id")
        if [ "$script_number" -lt 0 ]; then
            printf '%s\n' "KWin rejected the drag-target script reload." >&2
            exit 1
        fi
    else
        qdbus-qt6 \
            org.kde.KWin \
            /Scripting \
            org.kde.kwin.Scripting.unloadScript \
            "$package_id" >/dev/null || true
    fi

    floating_runtime_package="$data_directory/window-layouts-kde/runtime/$floating_package_id-$floating_runtime_version"
    install -d -m 755 \
        "$floating_runtime_package/contents/config" \
        "$floating_runtime_package/contents/images" \
        "$floating_runtime_package/contents/ui/components"
    install -m 644 \
        "$floating_package_directory/metadata.json" \
        "$floating_runtime_package/metadata.json"
    install -m 644 \
        "$floating_package_directory/contents/config/main.xml" \
        "$floating_runtime_package/contents/config/main.xml"
    install -m 644 \
        "$floating_package_directory/contents/images/window-layouts.svg" \
        "$floating_runtime_package/contents/images/window-layouts.svg"
    install -m 644 \
        "$floating_package_directory/contents/ui/main.qml" \
        "$floating_runtime_package/contents/ui/main.qml"
    install -m 644 \
        "$floating_package_directory/contents/ui/components/FloatingButton.qml" \
        "$floating_runtime_package/contents/ui/components/FloatingButton.qml"

    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.unloadScript \
        "$floating_package_id" >/dev/null || true
    if [ "$floating_enabled" = true ]; then
        floating_script_number=$(qdbus-qt6 \
            org.kde.KWin \
            /Scripting \
            org.kde.kwin.Scripting.loadDeclarativeScript \
            "$floating_runtime_package/contents/ui/main.qml" \
            "$floating_package_id")
        if [ "$floating_script_number" -lt 0 ]; then
            printf '%s\n' "KWin rejected the floating-button script reload." >&2
            exit 1
        fi
    fi

    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.start >/dev/null
fi

printf '%s\n' \
    "Window Layouts feature controls installed." \
    "Floating button enabled: $floating_enabled" \
    "Floating button size: $floating_button_size" \
    "Layout padding: ${layout_padding}px" \
    "Drag targets enabled: $drag_targets_enabled" \
    "Drag target placement: $drag_target_placement" \
    "Show zone targets immediately: $show_all_drag_targets" \
    "Show top-center targets immediately: $show_all_top_drag_targets" \
    "Layout group order: $group_order"
