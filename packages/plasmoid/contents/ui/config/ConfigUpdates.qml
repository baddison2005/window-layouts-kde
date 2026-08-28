/*
 * SPDX-FileCopyrightText: 2026 Dr. Bret Addison
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

KCM.SimpleKCM {
    id: page

    // Plasma passes every persisted cfg_* value into each configuration page.
    // These declarations ensure that visiting Updates never creates a partial
    // settings snapshot or marks unrelated controls as modified.
    property string cfg_customLayouts: "[]"
    property string cfg_customLayoutsDefault: "[]"
    property string cfg_customGroups: "[]"
    property string cfg_customGroupsDefault: "[]"
    property bool cfg_floatingButtonEnabled: false
    property bool cfg_floatingButtonEnabledDefault: false
    property bool cfg_dragTargetsEnabled: false
    property bool cfg_dragTargetsEnabledDefault: false
    property bool cfg_showAllDragTargets: false
    property bool cfg_showAllDragTargetsDefault: false
    property string cfg_dragTargetPlacement: "zones"
    property string cfg_dragTargetPlacementDefault: "zones"
    property bool cfg_showAllTopDragTargets: false
    property bool cfg_showAllTopDragTargetsDefault: false
    property string cfg_floatingButtonSize: "default"
    property string cfg_floatingButtonSizeDefault: "default"
    property int cfg_layoutPadding: 0
    property int cfg_layoutPaddingDefault: 0
    property string cfg_groupOrder: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"fillDisplay\",\"window\"]"
    property string cfg_groupOrderDefault: "[\"halves\",\"quarters\",\"thirds\",\"twoThirds\",\"custom\",\"fillDisplay\",\"window\"]"

    readonly property string currentVersion: "1.3.1"
    readonly property string projectUrl: "https://github.com/baddison2005/window-layouts-kde"
    readonly property string helpUrl: `${projectUrl}/issues`
    readonly property string releasesUrl: `${projectUrl}/releases`
    readonly property string helperPath: decodeURIComponent(
        Qt.resolvedUrl("../../tools/update.sh").toString().replace(/^file:\/\//, ""),
    )
    property string statusMessage: i18n("Installed version: %1", currentVersion)
    property int statusType: Kirigami.MessageType.Information
    property string latestVersion: ""
    property bool updateAvailable: false
    property bool canInstall: false
    property bool busy: false

    implicitWidth: Kirigami.Units.gridUnit * 34
    implicitHeight: Kirigami.Units.gridUnit * 32

    function runUpdater(action) {
        busy = true;
        statusType = Kirigami.MessageType.Information;
        statusMessage = action === "install"
            ? i18n("Downloading, verifying, and installing Window Layouts %1…", latestVersion)
            : i18n("Checking GitHub Releases…");
        updateRunner.connectSource(`${helperPath} ${action}`);
    }

    function showError(message) {
        busy = false;
        canInstall = false;
        statusType = Kirigami.MessageType.Error;
        statusMessage = message;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Layout.preferredWidth
                source: Qt.resolvedUrl("../../images/window-layouts.svg")
            }

            ColumnLayout {
                Layout.fillWidth: true

                Kirigami.Heading {
                    text: i18n("Window Layouts %1", page.currentVersion)
                    level: 1
                }

                Kirigami.Heading {
                    Layout.fillWidth: true
                    text: i18n("Your Workspace, Organized Your Way!")
                    level: 3
                    type: Kirigami.Heading.Type.Secondary
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("Flexible window positioning and layouts for KDE Plasma Wayland.")
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    text: i18n("Author: Dr. Bret Addison")
                }
            }
        }

        GridLayout {
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("Website") }
            Kirigami.UrlButton {
                text: page.projectUrl
                url: page.projectUrl
            }

            QQC2.Label { text: i18n("Get Help") }
            Kirigami.UrlButton {
                text: i18n("Report an issue on GitHub")
                url: page.helpUrl
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            text: i18n("Software Updates")
            level: 2
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Check GitHub Releases for a newer stable version. Installable updates are downloaded over HTTPS and applied only after their published SHA-256 checksum has been verified.")
            wrapMode: Text.WordWrap
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: text.length > 0
            text: page.statusMessage
            type: page.statusType
        }

        RowLayout {
            QQC2.Button {
                text: i18n("Check for Updates")
                icon.name: "view-refresh"
                enabled: !page.busy
                onClicked: page.runUpdater("check")
            }

            QQC2.Button {
                text: page.latestVersion.length > 0
                    ? i18n("Install v%1", page.latestVersion)
                    : i18n("Install Update")
                icon.name: "software-update-available"
                enabled: !page.busy && page.updateAvailable && page.canInstall
                onClicked: installConfirmation.open()
            }

            QQC2.BusyIndicator {
                running: page.busy
                visible: running
            }

            Item { Layout.fillWidth: true }

            Kirigami.UrlButton {
                text: i18n("View GitHub Releases")
                url: page.releasesUrl
            }
        }
    }

    QQC2.Dialog {
        id: installConfirmation
        parent: page
        anchors.centerIn: parent
        modal: true
        title: i18n("Install Window Layouts %1?", page.latestVersion)
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: page.runUpdater("install")

        contentItem: QQC2.Label {
            // Qt 6 exposes Control.implicitWidth as read-only here. Giving
            // the dialog content an explicit width avoids a QML load failure
            // when the Updates category is first opened.
            width: Kirigami.Units.gridUnit * 24
            text: i18n("Your existing layouts and feature settings will be preserved.")
            wrapMode: Text.WordWrap
        }
    }

    Plasma5Support.DataSource {
        id: updateRunner
        engine: "executable"

        onNewData: function(sourceName, data) {
            const exitCode = data["exit code"];
            if (exitCode !== undefined && exitCode !== 0) {
                page.showError(i18n(
                    "Could not run the update service: %1",
                    data.stderr || i18n("unknown error"),
                ));
                disconnectSource(sourceName);
                return;
            }
            try {
                const result = JSON.parse((data.stdout || "{}").trim());
                if (result.error) {
                    page.showError(i18n("Could not update Window Layouts: %1", result.error));
                } else if (sourceName.endsWith(" install")) {
                    page.busy = false;
                    page.updateAvailable = false;
                    page.canInstall = false;
                    page.statusType = Kirigami.MessageType.Positive;
                    page.statusMessage = result.installed
                        ? i18n("Window Layouts %1 was installed. Close and reopen this configuration window to load the updated About information.", result.latestVersion)
                        : i18n("Window Layouts is already up to date.");
                } else {
                    page.busy = false;
                    page.latestVersion = result.latestVersion || "";
                    page.updateAvailable = Boolean(result.updateAvailable);
                    page.canInstall = Boolean(result.canInstall);
                    if (page.updateAvailable) {
                        page.statusType = page.canInstall
                            ? Kirigami.MessageType.Positive
                            : Kirigami.MessageType.Warning;
                        page.statusMessage = page.canInstall
                            ? i18n("Window Layouts %1 is available.", page.latestVersion)
                            : (result.installReason || i18n("A manual update is available."));
                    } else {
                        page.statusType = Kirigami.MessageType.Positive;
                        page.statusMessage = i18n(
                            "Window Layouts %1 is up to date.",
                            page.currentVersion,
                        );
                    }
                }
            } catch (error) {
                page.showError(i18n("Could not read the update service response."));
            }
            disconnectSource(sourceName);
        }
    }
}
