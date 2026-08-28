#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Window Layouts contributors
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kwin_package="$project_dir/packages/kwin-script"
floating_package="$project_dir/packages/floating-button"
drag_overlay_package="$project_dir/packages/drag-overlay"
plasmoid_package="$project_dir/packages/plasmoid"
configurator_source="$project_dir/helpers/window-layouts-configurator-service"
configurator_ui_source="$project_dir/cairo-dock-applet/window-layouts/configurator.py"
updater_source="$project_dir/helpers/updater.py"
layout_transfer_source="$project_dir/helpers/layout_transfer.py"
bridge_workaround_source="$project_dir/helpers/xwayland-video-bridge-workaround"
version_source="$project_dir/VERSION"
logo_source="$project_dir/packages/plasmoid/contents/images/window-layouts.svg"
configurator_service_template="$project_dir/helpers/org.example.WindowLayouts.Configurator.service.in"

data_directory=$(qtpaths6 --writable-path GenericDataLocation)
configurator_directory="$data_directory/window-layouts-kde/configurator"
tools_directory="$data_directory/window-layouts-kde/tools"
dbus_service_directory="$data_directory/dbus-1/services"

install -d -m 755 \
    "$configurator_directory" \
    "$tools_directory" \
    "$dbus_service_directory"
install -m 755 "$configurator_source" "$configurator_directory/window-layouts-configurator-service"
install -m 644 "$configurator_ui_source" "$configurator_directory/configurator.py"
install -m 644 "$updater_source" "$configurator_directory/updater.py"
install -m 644 "$layout_transfer_source" "$configurator_directory/layout_transfer.py"
install -m 644 "$version_source" "$configurator_directory/VERSION"
install -m 644 "$logo_source" "$configurator_directory/window-layouts.svg"
install -m 755 \
    "$bridge_workaround_source" \
    "$tools_directory/xwayland-video-bridge-workaround"

configurator_service_file=$(mktemp)
trap 'rm -f "$configurator_service_file"' EXIT HUP INT TERM
sed \
    "s|@CONFIGURATOR_EXEC@|$configurator_directory/window-layouts-configurator-service|" \
    "$configurator_service_template" > "$configurator_service_file"
install -m 644 \
    "$configurator_service_file" \
    "$dbus_service_directory/org.example.WindowLayouts.Configurator.service"

if command -v dbus-send >/dev/null 2>&1; then
    dbus-send \
        --session \
        --type=method_call \
        --dest=org.freedesktop.DBus \
        / \
        org.freedesktop.DBus.ReloadConfig
fi

# A previously activated helper keeps running after its files are replaced.
# Stop that small process so the next Configure request loads this version.
if command -v qdbus-qt6 >/dev/null 2>&1; then
    qdbus-qt6 \
        org.example.WindowLayouts.Configurator \
        /org/example/WindowLayouts/Configurator \
        org.example.WindowLayouts.Configurator.Quit \
        >/dev/null 2>&1 || true
fi

install_or_upgrade() {
    package_type=$1
    package_id=$2
    package_path=$3

    if kpackagetool6 --type "$package_type" --show "$package_id" >/dev/null 2>&1; then
        kpackagetool6 --type "$package_type" --upgrade "$package_path"
    else
        kpackagetool6 --type "$package_type" --install "$package_path"
    fi
}

install_or_upgrade "KWin/Script" "windowlayouts" "$kwin_package"
install_or_upgrade "KWin/Script" "windowlayoutsfloatingbutton" "$floating_package"
install_or_upgrade "KWin/Script" "windowlayoutsdragtargets" "$drag_overlay_package"
install_or_upgrade "Plasma/Applet" "org.example.windowlayouts" "$plasmoid_package"

installed_config_page="$data_directory/plasma/plasmoids/org.example.windowlayouts/contents/ui/config/ConfigLayouts.qml"
if [ ! -f "$installed_config_page" ]; then
    printf '%s\n' \
        "Window Layouts installation failed: the panel configurator page is missing." \
        >&2
    exit 1
fi

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsEnabled \
    --type bool \
    true

# Disable the short-lived development ID used by the first prototype build.
kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsfloatingEnabled \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key ShowAllTargets \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key TargetPlacement \
    zones

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key ShowAllTopTargets \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsfloatingbutton \
    --key ButtonSize \
    default

for group in Script-windowlayouts Script-windowlayoutsdragtargets
do
    kwriteconfig6 \
        --file kwinrc \
        --group "$group" \
        --key LayoutPadding \
        --type int \
        0
done

default_group_order='["halves","quarters","thirds","twoThirds","custom","fillDisplay","window"]'
for group in \
    Script-windowlayouts \
    Script-windowlayoutsfloatingbutton \
    Script-windowlayoutsdragtargets
do
    kwriteconfig6 \
        --file kwinrc \
        --group "$group" \
        --key GroupOrder \
        "$default_group_order"
done

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsfloatingbuttonEnabled \
    --type bool \
    false

kwriteconfig6 \
    --file kwinrc \
    --group Plugins \
    --key windowlayoutsdragtargetsEnabled \
    --type bool \
    false

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
custom_groups_escaped=${custom_groups//\\/\\\\}
custom_groups_escaped=${custom_groups_escaped//\"/\\\"}
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
    --group Script-windowlayoutsfloatingbutton \
    --key CustomLayouts \
    "$custom_layouts"
kwriteconfig6 \
    --file kwinrc \
    --group Script-windowlayoutsdragtargets \
    --key CustomLayouts \
    "$custom_layouts"

if command -v qdbus-qt6 >/dev/null 2>&1; then
    settings_script='var updated = false;
for (var panelIndex = 0; panelIndex < panelIds.length && !updated; panelIndex++) {
    var panel = panelById(panelIds[panelIndex]);
    for (var widgetIndex = 0; widgetIndex < panel.widgetIds.length; widgetIndex++) {
        var widget = panel.widgetById(panel.widgetIds[widgetIndex]);
        if (widget && widget.type === "org.example.windowlayouts") {
            widget.currentConfigGroup = ["General"];
            widget.writeConfig("floatingButtonEnabled", false);
            widget.writeConfig("dragTargetsEnabled", false);
            widget.writeConfig("showAllDragTargets", false);
            widget.writeConfig("dragTargetPlacement", "zones");
            widget.writeConfig("showAllTopDragTargets", false);
            widget.writeConfig("floatingButtonSize", "default");
            widget.writeConfig("layoutPadding", 0);
            widget.writeConfig("groupOrder", "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"fillDisplay\",\"window\"]");
            updated = true;
            break;
        }
    }
}
print(updated ? "updated" : "missing");'
    qdbus-qt6 \
        org.kde.plasmashell \
        /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript \
        "$settings_script" >/dev/null || true

    layout_script="var updated = false;
for (var panelIndex = 0; panelIndex < panelIds.length && !updated; panelIndex++) {
    var panel = panelById(panelIds[panelIndex]);
    for (var widgetIndex = 0; widgetIndex < panel.widgetIds.length; widgetIndex++) {
        var widget = panel.widgetById(panel.widgetIds[widgetIndex]);
        if (widget && widget.type === \"org.example.windowlayouts\") {
            widget.currentConfigGroup = [\"General\"];
            widget.writeConfig(\"customLayouts\", \"$custom_layouts_escaped\");
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
        "$layout_script" >/dev/null || true

    qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null

    # Reconfigure enables installed scripts but does not replace the source of
    # an already-running instance. Reload the enabled action script through
    # KWin's scripting interface so package upgrades take effect without
    # ending the session. Explicitly unload the optional floating script to
    # enforce its safe disabled-by-default state.
    installed_main="$data_directory/kwin/scripts/windowlayouts/contents/code/main.js"
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.unloadScript \
        windowlayouts >/dev/null
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.loadScript \
        "$installed_main" \
        windowlayouts >/dev/null
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.unloadScript \
        windowlayoutsfloatingbutton >/dev/null || true
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.unloadScript \
        windowlayoutsdragtargets >/dev/null || true
    qdbus-qt6 \
        org.kde.KWin \
        /Scripting \
        org.kde.kwin.Scripting.start >/dev/null

fi

printf '%s\n' \
    "Window Layouts installed with its KWin actions enabled." \
    "The optional floating button and drag targets are installed but disabled by default." \
    "Run ./place-on-panel.sh to add its button to an existing Plasma panel."
