import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// One container: status line with start/stop buttons, details and more actions when expanded
ColumnLayout {
    id: containerRow

    property var widget
    property var container
    property bool indented: false

    readonly property bool busy: !!widget.busyIds[container.id]
    readonly property bool open: !!widget.openIds[container.id]
    readonly property bool hasWeb: container.url !== "" || container.ports.length > 0
    readonly property real indent: indented ? Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing : 0
    property bool confirmRemove: false

    readonly property color statusColor: {
        switch (container.level) {
        case "ok":
            return Kirigami.Theme.positiveTextColor;
        case "warn":
            return Kirigami.Theme.neutralTextColor;
        case "error":
            return Kirigami.Theme.negativeTextColor;
        default:
            return Kirigami.Theme.disabledTextColor;
        }
    }

    spacing: 0

    PlasmaComponents.ItemDelegate {
        Layout.fillWidth: true
        onClicked: containerRow.widget.toggleOpen(containerRow.container.id)

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.leftMargin: containerRow.indent + Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.preferredWidth: Kirigami.Units.iconSizes.small / 2
                Layout.preferredHeight: Layout.preferredWidth
                radius: width / 2
                color: containerRow.container.running ? containerRow.statusColor : "transparent"
                border.width: 2
                border.color: containerRow.statusColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents.Label {
                    text: containerRow.container.title
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: containerRow.container.image + " · " + containerRow.container.status
                    font: Kirigami.Theme.smallFont
                    color: containerRow.container.level === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    opacity: containerRow.container.level === "error" ? 1 : 0.7
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            ActionButton {
                visible: containerRow.container.running && containerRow.hasWeb
                icon.name: "globe"
                tip: i18n("Open web UI")
                onClicked: containerRow.widget.openWeb(containerRow.container)
            }

            PlasmaComponents.BusyIndicator {
                visible: containerRow.busy
                running: visible
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            ActionButton {
                visible: !containerRow.busy && !containerRow.container.running
                icon.name: "media-playback-start"
                tip: i18n("Start")
                onClicked: containerRow.widget.containerAction("start", [containerRow.container.id])
            }

            ActionButton {
                visible: !containerRow.busy && containerRow.container.running
                icon.name: "media-playback-stop"
                tip: i18n("Stop")
                onClicked: containerRow.widget.containerAction("stop", [containerRow.container.id])
            }

            ActionButton {
                visible: !containerRow.busy && containerRow.container.running
                icon.name: "system-reboot"
                tip: i18n("Restart")
                onClicked: containerRow.widget.containerAction("restart", [containerRow.container.id])
            }

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: containerRow.open ? "arrow-down" : "arrow-right"
                opacity: 0.7
            }
        }
    }

    ColumnLayout {
        visible: containerRow.open
        Layout.fillWidth: true
        Layout.leftMargin: containerRow.indent + Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 3
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            DetailLabel { text: i18n("Name") }
            DetailValue { text: containerRow.container.name }
            DetailLabel { text: i18n("Image") }
            DetailValue { text: containerRow.container.image }
            DetailLabel { text: i18n("Ports") }
            DetailValue { text: containerRow.container.portsText || "–" }
            DetailLabel { text: i18n("Networks") }
            DetailValue { text: containerRow.container.networks || "–" }
            DetailLabel { text: i18n("Created") }
            DetailValue { text: containerRow.container.created }
            DetailLabel { text: i18n("ID") }
            DetailValue { text: containerRow.container.id }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Button {
                visible: containerRow.container.url !== "" && containerRow.container.running
                icon.name: "globe"
                text: containerRow.container.url.replace(/^https?:\/\//, "")
                onClicked: containerRow.widget.openUrl(containerRow.container.url)
            }

            Repeater {
                model: containerRow.container.running ? containerRow.container.ports : []

                delegate: PlasmaComponents.Button {
                    required property var modelData
                    icon.name: "globe"
                    text: ":" + modelData.port
                    onClicked: containerRow.widget.openPort(modelData)
                }
            }

            PlasmaComponents.Button {
                icon.name: "view-list-text"
                text: i18n("Logs")
                onClicked: containerRow.widget.showLogs(containerRow.container.id)
            }

            PlasmaComponents.Button {
                visible: containerRow.container.state === "running"
                icon.name: "utilities-terminal"
                text: i18n("Shell")
                onClicked: containerRow.widget.openShell(containerRow.container.id)
            }

            PlasmaComponents.Button {
                icon.name: "edit-copy"
                text: i18n("Copy ID")
                onClicked: containerRow.widget.copyText(containerRow.container.id)
            }

            PlasmaComponents.Button {
                visible: !containerRow.container.running
                enabled: !containerRow.busy
                icon.name: "edit-delete"
                text: containerRow.confirmRemove ? i18n("Really remove?") : i18n("Remove")
                onClicked: {
                    if (containerRow.confirmRemove) {
                        containerRow.widget.containerAction("rm", [containerRow.container.id]);
                    }
                    containerRow.confirmRemove = !containerRow.confirmRemove;
                }

                Timer {
                    interval: 4000
                    running: containerRow.confirmRemove
                    onTriggered: containerRow.confirmRemove = false
                }
            }
        }
    }
}
