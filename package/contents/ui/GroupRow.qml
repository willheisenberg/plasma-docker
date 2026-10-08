import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Header of a compose project: collapses its containers and starts/stops all of them at once
PlasmaComponents.ItemDelegate {
    id: groupRow

    property var widget
    property var entry

    readonly property bool collapsed: !!widget.collapsedGroups[entry.key]
    readonly property bool busy: {
        var ids = entry.runningIds.concat(entry.stoppedIds);
        for (var i = 0; i < ids.length; i++) {
            if (widget.busyIds[ids[i]]) {
                return true;
            }
        }
        return false;
    }

    onClicked: widget.toggleGroup(entry.key)

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: groupRow.collapsed ? "arrow-right" : "arrow-down"
        }

        PlasmaComponents.Label {
            text: groupRow.entry.key
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            text: groupRow.entry.runningIds.length + "/" + (groupRow.entry.runningIds.length + groupRow.entry.stoppedIds.length)
            opacity: 0.7
        }

        PlasmaComponents.BusyIndicator {
            visible: groupRow.busy
            running: visible
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }

        ActionButton {
            visible: !groupRow.busy && groupRow.entry.stoppedIds.length > 0
            icon.name: "media-playback-start"
            tip: i18n("Start all")
            onClicked: groupRow.widget.containerAction("start", groupRow.entry.stoppedIds)
        }

        ActionButton {
            visible: !groupRow.busy && groupRow.entry.runningIds.length > 0
            icon.name: "media-playback-stop"
            tip: i18n("Stop all")
            onClicked: groupRow.widget.containerAction("stop", groupRow.entry.runningIds)
        }

        ActionButton {
            visible: !groupRow.busy && groupRow.entry.runningIds.length > 0
            icon.name: "system-reboot"
            tip: i18n("Restart all")
            onClicked: groupRow.widget.containerAction("restart", groupRow.entry.runningIds)
        }
    }
}
