#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

# Installs the optional Window Layouts UI features and their shared settings.
# Existing enabled/disabled states are preserved.

set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_directory="$project_directory/packages/drag-overlay"
floating_package_directory="$project_directory/packages/floating-button"
plasmoid_directory="$project_directory/packages/plasmoid"
configurator_source="$project_directory/helpers/window-layouts-configurator-service"
configurator_ui_source="$project_directory/cairo-dock-applet/window-layouts/configurator.py"
package_id="windowlayoutsdragtargets"
legacy_package_id="windowlayoutsdragoverlay"
runtime_version="0.1.4"
floating_package_id="windowlayoutsfloatingbutton"
floating_runtime_version="0.3.1"
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
floating_button_size=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsfloatingbutton \
    --key ButtonSize \
    --default default)
case "$floating_button_size" in
    small|default|big|extraBig) ;;
    *) floating_button_size=default ;;
esac
group_order=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key GroupOrder \
    --default '["halves","quarters","thirds","twoThirds","custom","window"]')
if ! printf '%s' "$group_order" \
    | grep -Eq '^\["(halves|quarters|thirds|twoThirds|custom|window)"(,"(halves|quarters|thirds|twoThirds|custom|window)")*\]$'
then
    group_order='["halves","quarters","thirds","twoThirds","custom","window"]'
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
    if command -v qdbus-qt6 >/dev/null 2>&1; then
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
fi

custom_layouts=$(kreadconfig6 \
    --file kwinrc \
    --group Script-windowlayouts \
    --key CustomLayouts \
    --default '[]')
kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key CustomLayouts \
    "$custom_layouts"

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
    --group Script-windowlayoutsfloatingbutton \
    --key ButtonSize \
    "$floating_button_size"

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
            widget.writeConfig(\"floatingButtonEnabled\", $floating_enabled);
            widget.writeConfig(\"dragTargetsEnabled\", $drag_targets_enabled);
            widget.writeConfig(\"showAllDragTargets\", $show_all_drag_targets);
            widget.writeConfig(\"floatingButtonSize\", \"$floating_button_size\");
            widget.writeConfig(\"groupOrder\", \"$group_order_escaped\");
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
    "Drag targets enabled: $drag_targets_enabled" \
    "Show all drag targets immediately: $show_all_drag_targets" \
    "Layout group order: $group_order"
