pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Pixel font catalog (scripts/fonts.py) and fonts picked for the UI.
// Fonts installed while the shell runs are unknown to Qt's font database,
// so every file from ~/.local/share/fonts/angelos is also loaded explicitly.
Singleton {
    id: root

    property var catalog: []
    property string busyId: ""
    property string error: ""
    readonly property bool busy: worker.running
    readonly property var files: catalog.reduce((all, f) => all.concat(f.files || []), [])
    // presets offered by the setup wizard: [title, body, mono]
    readonly property var presets: [
        {
            "id": "angelos",
            "label": "kukabara",
            "fonts": ["", "", ""],
            "needs": []
        },
        {
            "id": "arcade",
            "label": "Arcade",
            "fonts": ["Press Start 2P", "Tiny5", "Monocraft"],
            "needs": ["pressstart", "tiny5", "monocraft"]
        },
        {
            "id": "soft",
            "label": "Soft pixels",
            "fonts": ["Pixelify Sans", "Pixelify Sans", "Departure Mono"],
            "needs": ["pixelify", "departure"]
        },
        {
            "id": "block",
            "label": "Blocky",
            "fonts": ["Monocraft", "Monocraft", "Monocraft"],
            "needs": ["monocraft"]
        }
    ]

    function byId(id) {
        return catalog.find(f => f.id === id) || null;
    }
    function installed(id) {
        const f = byId(id);
        return !!f && f.installed;
    }
    // families a picker can offer: catalog fonts first, then everything else Qt knows
    function choices(role) {
        const out = [
            {
                "label": I18n.t("Как в kukabara", "kukabara default"),
                "value": ""
            }
        ];
        const seen = {};
        for (const f of catalog)
            for (const fam of f.families)
                if (!seen[fam]) {
                    seen[fam] = true;
                    if (f.installed)
                        out.push({
                            "label": fam + (f.roles.includes(role) ? " ♡" : "") + (f.cyrillic ? "" : I18n.t(" (латиница)", " (Latin only)")),
                            "value": fam
                        });
                }
        for (const fam of Qt.fontFamilies())
            if (!seen[fam] && !fam.startsWith(".")) {
                seen[fam] = true;
                out.push({
                    "label": fam,
                    "value": fam
                });
            }
        return out;
    }
    function apply(fonts) {
        Config.appearance.fontTitle = fonts[0];
        Config.appearance.fontBody = fonts[1];
        Config.appearance.fontMono = fonts[2];
    }
    function applyPreset(preset) {
        const missing = preset.needs.filter(id => !installed(id));
        if (missing.length) {
            _after = preset;
            _queue = missing.slice();
            _next();
            return;
        }
        apply(preset.fonts);
    }
    property var _after: null
    property var _queue: []
    function _next() {
        if (_queue.length > 0) {
            install(_queue.shift());
            return;
        }
        if (_after && !error)
            applyLater.restart();  // after the refreshed catalog registered the new files
        else
            _after = null;
    }
    Timer {
        id: applyLater
        interval: 600
        onTriggered: {
            if (root._after)
                root.apply(root._after.fonts);
            root._after = null;
        }
    }

    function refresh() {
        if (!lister.running)
            lister.running = true;
    }
    function install(id) {
        if (worker.running)
            return;
        busyId = id;
        error = "";
        worker.command = ["python3", Quickshell.shellDir + "/scripts/fonts.py", "install", id];
        worker.running = true;
    }
    function remove(id) {
        if (worker.running)
            return;
        const f = byId(id);
        // a removed family must not stay selected: Qt would silently fall back
        for (const key of ["fontTitle", "fontBody", "fontMono"])
            if (f && f.families.includes(Config.appearance[key]))
                Config.appearance[key] = "";
        busyId = id;
        error = "";
        worker.command = ["python3", Quickshell.shellDir + "/scripts/fonts.py", "remove", id];
        worker.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: lister
        command: ["python3", Quickshell.shellDir + "/scripts/fonts.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.catalog = JSON.parse(text).fonts || [];
                } catch (e) {
                    console.warn("kukabara fonts:", e);
                }
            }
        }
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.error)
                        root.error = r.error;
                } catch (e) {
                    root.error = I18n.t("Не удалось установить шрифт", "Could not install the font");
                }
            }
        }
        stderr: StdioCollector {}
        onExited: {
            root.busyId = "";
            root.refresh();
            if (root.error)
                root._queue = [];
            root._next();
        }
    }

    Instantiator {
        model: root.files
        delegate: FontLoader {
            required property string modelData
            source: "file://" + modelData
        }
    }
}
