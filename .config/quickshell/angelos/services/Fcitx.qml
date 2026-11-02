pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The input method fcitx5 runs, for the bar's layout widget (bar/parts/KbLayout): niri knows
// only its own xkb layouts, so a user whose layouts live in fcitx5 saw nothing on the bar
// (issue #136). scripts/fcitx-watch.py reads the controller over DBus and reports JSON lines;
// `next` / `prev` switch it the way its tray icon does. With fcitx5 not installed the helper
// says so and exits, and nothing here runs.
Singleton {
    id: root

    property bool installed: true      // fcitx5 is on this machine
    property bool available: false     // …and running with its DBus controller
    property string current: ""        // its unique name, e.g. keyboard-ru
    property string name: ""           // "Русская"
    property string label: ""          // "ru"
    property int count: 0              // input methods in the current group
    // what the bar shows: the short label, else the two letters of the name
    readonly property string shortLabel: {
        const l = String(root.label || "").trim();
        if (l)
            return l.length <= 3 && /^[A-Za-z0-9]+$/.test(l) ? l.toUpperCase() : l;
        const n = String(root.name || "").trim();
        const m = n.match(/\(([A-Z]{2})\)/);
        return m ? m[1] : n.slice(0, 2).toUpperCase();
    }
    // worth a place on the bar: fcitx5 runs and has something to switch between
    readonly property bool usable: root.available && root.count > 1
    readonly property bool wanted: Config.ready && root.installed

    function next() {
        _send("next");
    }
    function prev() {
        _send("prev");
    }
    function _send(cmd) {
        if (helper.running)
            helper.write(cmd + "\n");
    }
    function _event(line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (ev.installed === false) {
            root.installed = false;
            root.available = false;
            return;
        }
        root.available = ev.available === true;
        if (!root.available) {
            root.current = "";
            root.name = "";
            root.label = "";
            root.count = 0;
            return;
        }
        root.current = ev.current || "";
        root.name = ev.name || "";
        root.label = ev.label || "";
        root.count = ev.count || 0;
    }

    Process {
        id: helper
        running: root.wanted
        command: ["python3", "-u", Quickshell.shellDir + "/scripts/fcitx-watch.py"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root._event(line)
        }
        stderr: SplitParser {
            onRead: line => console.log("fcitx:", line)
        }
        onExited: if (root.wanted)
            restart.start()
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: if (root.wanted)
            helper.running = true
    }
}
