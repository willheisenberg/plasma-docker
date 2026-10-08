import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property var cfg_servers: []
    property alias cfg_dockerBinary: dockerBinaryField.text
    property alias cfg_terminalCommand: terminalCommandField.text
    property alias cfg_refreshInterval: refreshIntervalField.value
    property alias cfg_backgroundInterval: backgroundIntervalField.value
    property alias cfg_showCount: showCountField.checked

    Component.onCompleted: serversField.text = (cfg_servers || []).join("\n")

    TextArea {
        id: serversField
        Kirigami.FormData.label: i18n("Remote servers:")
        Kirigami.FormData.labelAlignment: Qt.AlignTop
        placeholderText: "user@192.168.1.50\nmyserver"
        Layout.fillWidth: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 5
        onTextChanged: {
            var out = [];
            var lines = text.split("\n");
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].trim() !== "") {
                    out.push(lines[i].trim());
                }
            }
            page.cfg_servers = out;
        }
    }

    Label {
        text: i18n("One SSH target per line: user@host, an IP address or a Host alias from ~/.ssh/config.\nlocalhost is always available. Login must work with a key, without a password prompt.")
        font.italic: true
        font.pointSize: 9
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    TextField {
        id: dockerBinaryField
        Kirigami.FormData.label: i18n("Docker command:")
        placeholderText: "docker"
        Layout.fillWidth: true
    }

    TextField {
        id: terminalCommandField
        Kirigami.FormData.label: i18n("Terminal for logs and shell:")
        placeholderText: i18n("System default (e.g. konsole -e)")
        Layout.fillWidth: true
    }

    SpinBox {
        id: refreshIntervalField
        Kirigami.FormData.label: i18n("Refresh while open (seconds):")
        from: 1
        to: 600
    }

    SpinBox {
        id: backgroundIntervalField
        Kirigami.FormData.label: i18n("Refresh in background (seconds, 0 = off):")
        from: 0
        to: 3600
    }

    CheckBox {
        id: showCountField
        Kirigami.FormData.label: i18n("Panel:")
        text: i18n("Show number of running containers")
    }
}
