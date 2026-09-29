/*
    SPDX-FileCopyrightText: 2026 Antti Jalomäki
    SPDX-License-Identifier: MIT
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.components as WorkspaceComponents

PlasmoidItem {
    id: root

    readonly property var presets: [50, 80, 90, 100]
    // The helper ships inside this widget. The first change installs a copy here (see README).
    readonly property string installedHelper: "/usr/local/libexec/plasma-charge-limit-helper"
    readonly property string bundledHelper: decodeURIComponent(Qt.resolvedUrl("../scripts/chargelimit-helper").toString().replace(/^file:\/\//, ""))

    property bool loaded: false
    property int limit: 0 // 0 when there is no battery with a charge limit
    property int capacity: 0
    property string batteryState: ""
    property string helperState: "setup" // "ready", "setup" or "outdated"
    property int pending: 0 // the limit being applied
    property string error: ""

    property var callbacks: ({})
    property int commandCount: 0

    Plasmoid.icon: limit ? `battery-${String(Math.round(limit / 10) * 10).padStart(3, "0")}` : "battery-missing"
    Plasmoid.status: limit ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: i18n("Charge Limit")
    toolTipSubText: limit ? i18n("Stops charging at %1%", limit) : i18n("No battery with a charge limit found")

    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 6

    onExpandedChanged: if (root.expanded) root.refresh()

    compactRepresentation: MouseArea {
        property bool wasExpanded

        hoverEnabled: true
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Kirigami.Icon {
            id: icon
            anchors.fill: parent
            source: Plasmoid.icon
            active: parent.containsMouse
        }

        WorkspaceComponents.BadgeOverlay {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.limit > 0
            text: i18nc("charge limit on the panel icon", "%1%", root.limit)
            icon: icon
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        spacing: Kirigami.Units.largeSpacing

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
            visible: root.loaded && !root.limit
            iconName: "battery-missing"
            text: i18n("No battery with a charge limit found")
        }

        PlasmaComponents3.Label {
            visible: root.limit > 0
            text: i18n("Stop charging at")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.limit > 0

            Repeater {
                model: root.presets

                PlasmaComponents3.Button {
                    required property int modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1 // equal widths
                    text: i18nc("charge limit preset", "%1%", modelData)
                    checked: root.limit === modelData
                    enabled: !root.pending
                    onClicked: root.setLimit(modelData)
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.limit > 0
            text: root.batteryState
                ? i18n("Battery at %1%, %2", root.capacity, root.batteryState.toLowerCase())
                : i18n("Battery at %1%", root.capacity)
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.limit > 0 && root.helperState !== "ready" && !root.error
            text: i18n("The first change asks for your password once.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.error !== ""
            text: root.error
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
        }

        Item {
            Layout.fillHeight: true // keeps the content at the top when there is room to spare
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            const done = root.callbacks[source]
            delete root.callbacks[source]
            if (done) {
                done(data["exit code"], data.stdout.trim(), data.stderr.trim())
            }
        }
    }

    // Runs a shell command and calls done(exitCode, stdout, stderr) when it finishes.
    function run(command, done) {
        const source = `${command} # ${++commandCount}` // unique, so a repeated command runs again
        callbacks[source] = done
        shell.connectSource(source)
    }

    function quote(text) {
        return `'${text.replace(/'/g, `'\\''`)}'`
    }

    function refresh() {
        run(`/bin/bash ${quote(bundledHelper)} status`, (code, stdout, stderr) => {
            const status = {}
            for (const line of stdout.split("\n")) {
                const i = line.indexOf("=")
                if (i > 0) {
                    status[line.slice(0, i)] = line.slice(i + 1)
                }
            }
            loaded = true
            limit = parseInt(status.limit) || 0
            capacity = parseInt(status.capacity) || 0
            batteryState = status.state || ""
            helperState = status.helper || "setup"
            if (code !== 0) {
                error = stderr || i18n("Could not read the charge limit.")
            }
        })
    }

    function setLimit(value) {
        pending = value
        error = ""
        const command = helperState === "ready"
            ? `pkexec ${installedHelper} set ${value}`
            : `pkexec /bin/bash ${quote(bundledHelper)} install ${value}`
        run(command, (code, stdout, stderr) => {
            pending = 0
            if (code === 0) {
                // Let Plasma's own battery widget pick up the new limit too.
                run("gdbus call --session --dest org.kde.Solid.PowerManagement --object-path /org/kde/Solid/PowerManagement --method org.kde.Solid.PowerManagement.reparseConfiguration", null)
            } else if (code !== 126) { // 126: the password dialog was dismissed
                error = stderr.split("\n")[0] || i18n("Could not change the charge limit.")
            }
            refresh()
        })
    }
}
