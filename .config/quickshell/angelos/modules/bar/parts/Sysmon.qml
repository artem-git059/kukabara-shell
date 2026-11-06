import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// The status bar's system module (the "statusbar" taskbar look): CPU and RAM load, and the
// network's speed, in one line. Read from /proc/stat, /proc/meminfo and /proc/net/dev every
// 2 s — the same sources as the desktop's SysmonWidget, only the numbers the bar needs.
Item {
    id: root

    required property string screenName
    // a taskbar on the left or the right edge (BarItem): the numbers in a short column
    property bool vertical: false

    property real cpu: 0
    property real ram: 0
    property string ramText: ""
    property real rx: 0
    property real tx: 0
    property var _cpuLast: null
    property var _netLast: null

    // stand still under a fullscreen game or the lock screen (the bar is still there)
    readonly property bool seen: visible && !Shell.hiddenScreen(screenName)
    // the bubble over it (BarItem), screen readers and the self-test
    readonly property string readout: I18n.t("Процессор ", "CPU ") + Math.round(cpu * 100) + "%, " + I18n.t("память ", "RAM ") + Math.round(ram * 100) + "%" + (ramText ? " (" + ramText + ")" : "") + ", ↓ " + human(rx) + ", ↑ " + human(tx)
    readonly property string barTip: readout
    Accessible.name: I18n.t("Процессор, память и сеть", "CPU, memory and network")
    Accessible.description: barTip

    implicitWidth: vertical ? col.implicitWidth + Theme.u * 4 : row.implicitWidth + Theme.u * 6
    implicitHeight: vertical ? col.implicitHeight : row.implicitHeight

    function human(bps) {
        const k = bps / 1024;
        return k < 1024 ? Math.round(k) + " " + I18n.t("КБ/с", "KB/s") : (k / 1024).toFixed(1) + " " + I18n.t("МБ/с", "MB/s");
    }
    // the bar's line: 1.2M, 40K — the unit once, in the tooltip
    function short(bps) {
        const k = bps / 1024;
        return k < 1024 ? Math.round(k) + "K" : (k / 1024).toFixed(1) + "M";
    }

    Timer {
        interval: 2000
        running: root.seen
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            mem.reload();
            net.reload();
        }
    }
    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
            if (root._cpuLast && total > root._cpuLast.t)
                root.cpu = Math.max(0, Math.min(1, 1 - (idle - root._cpuLast.i) / (total - root._cpuLast.t)));
            root._cpuLast = {
                "t": total,
                "i": idle
            };
        }
    }
    FileView {
        id: mem
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const g = k => parseInt((t.match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
            const total = g("MemTotal"), avail = g("MemAvailable");
            root.ram = 1 - avail / Math.max(1, total);
            root.ramText = ((total - avail) / 1048576).toFixed(1) + " / " + (total / 1048576).toFixed(0) + " " + I18n.t("ГБ", "GB");
        }
    }
    FileView {
        id: net
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const l of text().split("\n").slice(2)) {
                const m = l.trim().split(/[:\s]+/);
                if (!m[0] || m[0] === "lo" || m[0].startsWith("veth") || m[0].startsWith("docker"))
                    continue;
                rx += parseInt(m[1]) || 0;
                tx += parseInt(m[9]) || 0;
            }
            const now = Date.now();
            if (root._netLast) {
                const dt = (now - root._netLast.at) / 1000;
                root.rx = Math.max(0, (rx - root._netLast.rx) / dt);
                root.tx = Math.max(0, (tx - root._netLast.tx) / dt);
            }
            root._netLast = {
                "rx": rx,
                "tx": tx,
                "at": now
            };
        }
    }

    Row {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: Theme.u * 5

        // CPU
        Row {
            spacing: Theme.u * 2
            PxIcon {
                name: "chip"
                pixel: Math.max(1, Theme.u - 1)
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: Math.round(root.cpu * 100) + "%"
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        // RAM
        Row {
            spacing: Theme.u * 2
            PxIcon {
                name: "hdd"
                pixel: Math.max(1, Theme.u - 1)
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: Math.round(root.ram * 100) + "%"
                color: Theme.accent4
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        // network
        Row {
            spacing: Theme.u * 2
            PxText {
                text: "↓"
                color: Theme.ok
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: root.short(root.rx)
                kind: "tiny"
                color: Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: "↑"
                color: Theme.accent2
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: root.short(root.tx)
                kind: "tiny"
                color: Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // upright bar: one reading a line, narrow enough for the column
    Column {
        id: col
        visible: root.vertical
        anchors.centerIn: parent
        spacing: Theme.u * 2
        Row {
            spacing: Theme.u * 2
            PxIcon {
                name: "chip"
                pixel: Math.max(1, Theme.u - 1)
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: Math.round(root.cpu * 100) + "%"
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            spacing: Theme.u * 2
            PxIcon {
                name: "hdd"
                pixel: Math.max(1, Theme.u - 1)
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: Math.round(root.ram * 100) + "%"
                color: Theme.accent4
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            spacing: Theme.u * 2
            PxText {
                text: "↓"
                color: Theme.ok
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: root.short(root.rx)
                kind: "tiny"
                color: Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            spacing: Theme.u * 2
            PxText {
                text: "↑"
                color: Theme.accent2
                anchors.verticalCenter: parent.verticalCenter
            }
            PxText {
                text: root.short(root.tx)
                kind: "tiny"
                color: Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
