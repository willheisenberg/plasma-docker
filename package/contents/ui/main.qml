import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // Parsed `docker ps -a` output of the current server
    property var containers: []
    property string lastListText: ""
    property string loadError: ""
    property string actionError: ""
    property bool loading: false
    property bool loadedOnce: false

    // Per container / compose project UI state, keyed by container id or project name
    property var busyIds: ({})
    property var openIds: ({})
    property var collapsedGroups: ({})

    // Pending shell commands → callback(exitCode, stdout, stderr)
    property var callbacks: ({})

    readonly property var servers: {
        var out = [];
        var raw = Plasmoid.configuration.servers || [];
        for (var i = 0; i < raw.length; i++) {
            var s = String(raw[i]).trim();
            if (s !== "" && out.indexOf(s) < 0) {
                out.push(s);
            }
        }
        return out;
    }
    // SSH target of the selected server, "" means localhost
    readonly property string currentServer: servers.indexOf(Plasmoid.configuration.currentServer) >= 0 ? Plasmoid.configuration.currentServer : ""
    readonly property string serverLabel: currentServer !== "" ? currentServer : "localhost"

    readonly property string dockerBin: (Plasmoid.configuration.dockerBinary || "").trim() || "docker"
    readonly property string listCmd: "timeout 20 " + dockerCmd(["ps", "-a", "--format", "{{json .}}"], false)

    readonly property int runningCount: {
        var n = 0;
        for (var i = 0; i < containers.length; i++) {
            if (containers[i].running) {
                n++;
            }
        }
        return n;
    }
    readonly property bool hasProblem: {
        for (var i = 0; i < containers.length; i++) {
            if (containers[i].level === "error" || containers[i].level === "warn") {
                return true;
            }
        }
        return loadError !== "";
    }

    // Flat list for the popup: compose projects with their containers first, then the rest
    readonly property var rows: {
        var groups = {};
        var order = [];
        var single = [];
        var i, c;
        for (i = 0; i < containers.length; i++) {
            c = containers[i];
            if (c.project === "") {
                single.push(c);
                continue;
            }
            if (!groups[c.project]) {
                groups[c.project] = [];
                order.push(c.project);
            }
            groups[c.project].push(c);
        }
        order.sort();
        var out = [];
        for (i = 0; i < order.length; i++) {
            var members = groups[order[i]];
            var runningIds = [];
            var stoppedIds = [];
            for (var j = 0; j < members.length; j++) {
                (members[j].running ? runningIds : stoppedIds).push(members[j].id);
            }
            out.push({ kind: "group", key: order[i], runningIds: runningIds, stoppedIds: stoppedIds });
            for (j = 0; j < members.length; j++) {
                out.push({ kind: "container", groupKey: order[i], container: members[j] });
            }
        }
        if (single.length > 0 && order.length > 0) {
            out.push({ kind: "header", title: i18n("Standalone containers") });
        }
        for (i = 0; i < single.length; i++) {
            out.push({ kind: "container", groupKey: "", container: single[i] });
        }
        return out;
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function firstLine(s) {
        var lines = String(s || "").trim().split("\n");
        return lines[lines.length - 1].trim();
    }

    // BatchMode keeps a missing key or unknown host from hanging on a prompt nobody can see;
    // the shared control socket avoids a full SSH login for every single docker call.
    function sshCmd(interactive) {
        return "ssh " + (interactive ? "-t" : "-o BatchMode=yes") + " -o ConnectTimeout=5"
            + " -o ControlMaster=auto -o ControlPersist=120"
            + " -o ControlPath=\"${XDG_RUNTIME_DIR:-/tmp}/plasma-docker-%C\""
            + " -- " + shellQuote(currentServer);
    }

    function dockerCmd(args, interactive) {
        var cmd = dockerBin;
        for (var i = 0; i < args.length; i++) {
            cmd += " " + shellQuote(args[i]);
        }
        if (currentServer === "") {
            return cmd;
        }
        return sshCmd(interactive) + " " + shellQuote(cmd);
    }

    function exec(cmd, callback) {
        if (callbacks[cmd]) {
            return false;
        }
        callbacks[cmd] = callback;
        executable.connectSource(cmd);
        return true;
    }

    function runDetached(shellCmd) {
        exec("setsid -f sh -c " + shellQuote(shellCmd) + " >/dev/null 2>&1", function() {});
    }

    function refresh() {
        var cmd = listCmd;
        var started = exec(cmd, function(code, out, err) {
            // Server or docker binary was changed while this was running
            if (cmd !== root.listCmd) {
                return;
            }
            root.loading = false;
            root.loadedOnce = true;
            if (code !== 0) {
                root.lastListText = "";
                root.containers = [];
                root.loadError = code === 124 ? i18n("Timed out waiting for %1", root.serverLabel)
                                              : (firstLine(err) || i18n("%1 exited with code %2", root.dockerBin, code));
                return;
            }
            root.loadError = "";
            // Keep the existing delegates if nothing changed
            if (out === root.lastListText) {
                return;
            }
            root.lastListText = out;
            root.containers = parseList(out);
        });
        if (started) {
            loading = true;
        }
    }

    function parseList(text) {
        var out = [];
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line === "") {
                continue;
            }
            var c;
            try {
                c = JSON.parse(line);
            } catch (e) {
                continue;
            }
            var labels = parseLabels(c.Labels);
            var name = Array.isArray(c.Names) ? String(c.Names[0] || "") : String(c.Names || "").split(",")[0];
            var state = String(c.State || "").toLowerCase();
            var status = String(c.Status || "");
            var running = state === "running" || state === "restarting" || state === "paused";
            var project = labels["com.docker.compose.project"] || "";
            out.push({
                id: String(c.ID || ""),
                name: name,
                title: project !== "" && labels["com.docker.compose.service"] ? labels["com.docker.compose.service"] : name,
                image: String(c.Image || "").replace(/@sha256:.*$/, ""),
                state: state,
                status: status,
                running: running,
                level: statusLevel(state, status),
                ports: parsePorts(c.Ports),
                portsText: typeof c.Ports === "string" ? c.Ports : "",
                project: project,
                url: labels["plasma-docker.url"] || traefikUrl(labels),
                created: String(c.CreatedAt || ""),
                networks: String(c.Networks || "")
            });
        }
        out.sort(function(a, b) {
            return a.title.localeCompare(b.title);
        });
        return out;
    }

    // docker prints labels as "k=v,k=v"; a piece without its own key is the rest of a value with a comma in it
    function parseLabels(raw) {
        if (raw && typeof raw === "object") {
            return raw;
        }
        var out = {};
        var key = "";
        var parts = String(raw || "").split(",");
        for (var i = 0; i < parts.length; i++) {
            var eq = parts[i].indexOf("=");
            if (eq > 0 && /^[A-Za-z0-9_.\/-]+$/.test(parts[i].substring(0, eq))) {
                key = parts[i].substring(0, eq);
                out[key] = parts[i].substring(eq + 1);
            } else if (key !== "") {
                out[key] += "," + parts[i];
            }
        }
        return out;
    }

    // "ok" (running), "warn" (starting, unhealthy, restarting, paused), "error" (crashed), "off" (stopped)
    function statusLevel(state, status) {
        switch (state) {
        case "running":
            return /unhealthy|health: starting/.test(status) ? "warn" : "ok";
        case "restarting":
        case "paused":
            return "warn";
        case "dead":
            return "error";
        case "exited":
            var m = /\((\d+)\)/.exec(status);
            var code = m ? parseInt(m[1]) : 0;
            // 143 and 137 are what a plain `docker stop` leaves behind (SIGTERM / SIGKILL after the grace period)
            return code === 0 || code === 143 || code === 137 ? "off" : "error";
        default:
            return "off";
        }
    }

    // Published TCP ports, one entry per host port
    function parsePorts(raw) {
        var out = [];
        var seen = {};
        var re = /(\d+)(?:-\d+)?->(\d+)(?:-\d+)?\/tcp/g;
        var m;
        while ((m = re.exec(String(raw || ""))) !== null) {
            if (seen[m[1]]) {
                continue;
            }
            seen[m[1]] = true;
            out.push({ port: m[1], scheme: m[2] === "443" || m[2] === "8443" ? "https" : "http" });
        }
        return out;
    }

    function traefikUrl(labels) {
        for (var key in labels) {
            var m = /^(traefik\.http\.routers\.[^.]+)\.rule$/.exec(key);
            if (!m) {
                continue;
            }
            var host = /Host\(\s*`([^`]+)`/.exec(labels[key]);
            if (!host) {
                continue;
            }
            var tls = labels[m[1] + ".tls"] !== undefined || labels[m[1] + ".tls.certresolver"] !== undefined
                || /websecure|https/.test(labels[m[1] + ".entrypoints"] || "");
            return (tls ? "https" : "http") + "://" + host[1];
        }
        return "";
    }

    function setFlag(map, key, on) {
        var copy = Object.assign({}, map);
        if (on) {
            copy[key] = true;
        } else {
            delete copy[key];
        }
        return copy;
    }

    function toggleOpen(id) {
        openIds = setFlag(openIds, id, !openIds[id]);
    }

    function toggleGroup(key) {
        collapsedGroups = setFlag(collapsedGroups, key, !collapsedGroups[key]);
    }

    // action: start, stop, restart or rm
    function containerAction(action, ids) {
        if (ids.length === 0) {
            return;
        }
        var i;
        var busy = Object.assign({}, busyIds);
        for (i = 0; i < ids.length; i++) {
            busy[ids[i]] = true;
        }
        var started = exec("timeout 120 " + dockerCmd([action].concat(ids), false), function(code, out, err) {
            var done = Object.assign({}, root.busyIds);
            for (var k = 0; k < ids.length; k++) {
                delete done[ids[k]];
            }
            root.busyIds = done;
            root.actionError = code === 0 ? "" : (firstLine(err) || i18n("%1 %2 failed with code %3", root.dockerBin, action, code));
            root.refresh();
        });
        if (started) {
            busyIds = busy;
        }
    }

    function openUrl(url) {
        runDetached("xdg-open " + shellQuote(url));
    }

    function openPort(entry) {
        if (currentServer === "") {
            openUrl(entry.scheme + "://localhost:" + entry.port);
            return;
        }
        // The configured target may be an alias from ~/.ssh/config, so ask ssh for the real host name
        runDetached("h=$(ssh -G -- " + shellQuote(currentServer) + " | awk '$1==\"hostname\"{print $2; exit}'); "
            + "xdg-open " + shellQuote(entry.scheme + "://") + "\"$h\"" + shellQuote(":" + entry.port));
    }

    function openWeb(container) {
        if (container.url !== "") {
            openUrl(container.url);
        } else if (container.ports.length > 0) {
            openPort(container.ports[0]);
        }
    }

    function openTerminal(args, hold) {
        var inner = dockerCmd(args, true);
        if (hold) {
            inner += "; echo; printf '%s' " + shellQuote(i18n("[finished – press Enter to close]")) + "; read -r _";
        }
        var custom = (Plasmoid.configuration.terminalCommand || "").trim();
        var launcher = custom !== "" ? custom
            : "\"$(t=$(kreadconfig6 --file kdeglobals --group General --key TerminalApplication 2>/dev/null); echo \"${t:-konsole}\")\" -e";
        runDetached(launcher + " sh -c " + shellQuote(inner));
        root.expanded = false;
    }

    function showLogs(id) {
        openTerminal(["logs", "-f", "--tail", "200", id], true);
    }

    function openShell(id) {
        openTerminal(["exec", "-it", id, "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh"], false);
    }

    function copyText(text) {
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

    function selectServer(target) {
        Plasmoid.configuration.currentServer = target;
    }

    onExpandedChanged: function() {
        if (root.expanded) {
            refresh();
        }
    }
    onListCmdChanged: {
        lastListText = "";
        containers = [];
        loadError = "";
        actionError = "";
        loadedOnce = false;
        loading = false;
        refresh();
    }
    Component.onCompleted: refresh()

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    toolTipMainText: i18n("Docker Containers")
    toolTipSubText: loadError !== "" ? serverLabel + ": " + loadError
                                     : i18n("%1: %2 of %3 running", serverLabel, runningCount, containers.length)

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var callback = root.callbacks[sourceName];
            delete root.callbacks[sourceName];
            disconnectSource(sourceName);
            if (callback) {
                callback(data["exit code"], data["stdout"] || "", data["stderr"] || "");
            }
        }
    }

    Timer {
        interval: (root.expanded ? Plasmoid.configuration.refreshInterval : Plasmoid.configuration.backgroundInterval) * 1000
        running: interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    TextEdit {
        id: clipboardHelper
        visible: false
    }

    compactRepresentation: MouseArea {
        id: compactRoot

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property bool countVisible: Plasmoid.configuration.showCount && !vertical && root.loadedOnce && root.loadError === ""
        property bool wasExpanded: false

        Layout.minimumWidth: vertical ? Kirigami.Units.iconSizes.small : row.implicitWidth
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: !vertical
        Layout.minimumHeight: vertical ? Kirigami.Units.iconSizes.smallMedium : 0

        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            height: parent.height
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.alignment: Qt.AlignVCenter
                source: Qt.resolvedUrl("../icons/docker-symbolic.svg")
                isMask: true
                color: Kirigami.Theme.textColor
                active: compactRoot.containsMouse
            }

            PlasmaComponents.Label {
                visible: compactRoot.countVisible
                text: root.runningCount
                color: root.hasProblem ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    fullRepresentation: Item {
        id: popup

        // Grow with the content; only scroll if the list would not fit on screen
        readonly property real maxHeight: Screen.desktopAvailableHeight * 0.8
        readonly property real wantedHeight: Math.max(Kirigami.Units.gridUnit * 10, Math.min(content.implicitHeight, maxHeight))

        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: wantedHeight
        Layout.preferredHeight: wantedHeight
        Layout.maximumHeight: wantedHeight

        ColumnLayout {
            id: content
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.ComboBox {
                    id: serverBox
                    visible: root.servers.length > 0
                    model: ["localhost"].concat(root.servers)
                    onActivated: function(index) {
                        root.selectServer(index === 0 ? "" : root.servers[index - 1]);
                    }

                    // Not a binding: picking an entry would break it
                    function syncIndex() {
                        currentIndex = root.servers.indexOf(root.currentServer) + 1;
                    }
                    onModelChanged: syncIndex()
                    Component.onCompleted: syncIndex()

                    Connections {
                        target: root
                        function onCurrentServerChanged() {
                            serverBox.syncIndex();
                        }
                    }
                }

                PlasmaComponents.Label {
                    visible: !serverBox.visible
                    text: "localhost"
                    font.bold: true
                    leftPadding: Kirigami.Units.smallSpacing
                }

                Item {
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    visible: root.loadedOnce && root.loadError === ""
                    text: i18n("%1 of %2 running", root.runningCount, root.containers.length)
                    opacity: 0.7
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.loading
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip.text: i18n("Refresh")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                PlasmaComponents.ToolButton {
                    icon.name: "configure"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                    PlasmaComponents.ToolTip.text: i18n("Configure servers…")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                id: errorMessage
                text: root.actionError
                visible: false
                showCloseButton: true
                onVisibleChanged: {
                    if (!visible) {
                        root.actionError = "";
                    }
                }

                // Not a binding: the close button sets visible itself
                Connections {
                    target: root
                    function onActionErrorChanged() {
                        errorMessage.visible = root.actionError !== "";
                    }
                }
            }

            PlasmaComponents.ScrollView {
                id: scrollView
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: list.implicitHeight
                visible: root.rows.length > 0

                Column {
                    id: list
                    width: scrollView.availableWidth

                    Repeater {
                        model: root.rows

                        delegate: Loader {
                            id: rowLoader

                            required property var modelData

                            width: list.width
                            visible: modelData.kind !== "container" || !root.collapsedGroups[modelData.groupKey]
                            sourceComponent: modelData.kind === "group" ? groupComponent
                                           : modelData.kind === "header" ? headerComponent : containerComponent

                            Component {
                                id: groupComponent
                                GroupRow {
                                    widget: root
                                    entry: rowLoader.modelData
                                }
                            }

                            Component {
                                id: headerComponent
                                Kirigami.ListSectionHeader {
                                    text: rowLoader.modelData.title
                                }
                            }

                            Component {
                                id: containerComponent
                                ContainerRow {
                                    widget: root
                                    container: rowLoader.modelData.container
                                    indented: rowLoader.modelData.groupKey !== ""
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: placeholder.implicitHeight + Kirigami.Units.gridUnit * 2
                visible: root.rows.length === 0

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    visible: !root.loadedOnce
                    running: visible
                }

                PlasmaExtras.PlaceholderMessage {
                    id: placeholder
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 2
                    visible: root.loadedOnce
                    iconName: root.loadError !== "" ? "dialog-error" : ""
                    text: root.loadError !== "" ? i18n("Cannot reach Docker on %1", root.serverLabel) : i18n("No containers")
                    explanation: root.loadError
                }
            }
        }
    }
}
