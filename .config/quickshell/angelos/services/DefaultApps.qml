pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Default applications (xdg-mime), used by Settings → По умолчанию.
Singleton {
    id: root

    property var data: ({})
    property string log: ""
    readonly property bool busy: lister.running || setter.running

    readonly property var categories: [
        {
            "id": "browser",
            "label": I18n.t("Браузер", "Web browser"),
            "icon": "search"
        },
        {
            "id": "editor",
            "label": I18n.t("Текстовый редактор", "Text editor"),
            "icon": "terminal"
        },
        {
            "id": "files",
            "label": I18n.t("Файлы", "File manager"),
            "icon": "folder"
        },
        {
            "id": "terminal",
            "label": I18n.t("Терминал", "Terminal"),
            "icon": "terminal"
        },
        {
            "id": "image",
            "label": I18n.t("Картинки", "Images"),
            "icon": "image"
        },
        {
            "id": "video",
            "label": I18n.t("Видео", "Video"),
            "icon": "play"
        },
        {
            "id": "audio",
            "label": I18n.t("Музыка", "Music"),
            "icon": "music"
        },
        {
            "id": "pdf",
            "label": "PDF",
            "icon": "package"
        },
        {
            "id": "mail",
            "label": I18n.t("Почта", "Email"),
            "icon": "bell"
        },
        {
            "id": "archive",
            "label": I18n.t("Архивы", "Archives"),
            "icon": "package"
        }
    ]

    function refresh() {
        lister.command = ["python3", Quickshell.shellDir + "/scripts/default-apps.py", "list", Config.appearance.language || "ru"];
        lister.running = true;
    }
    function set(category, id) {
        if (setter.running || !id)
            return;
        setter.command = ["python3", Quickshell.shellDir + "/scripts/default-apps.py", "set", category, id];
        setter.running = true;
        // kukabara's own launchers follow the choice
        const e = DesktopEntries.byId(id.replace(/\.desktop$/, "")) || DesktopEntries.byId(id);
        const bin = e && e.command && e.command.length ? e.command[0] : id.replace(/\.desktop$/, "");
        if (category === "terminal")
            Config.system.terminal = bin;
        else if (category === "files")
            Config.system.fileManager = bin;
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text);
                } catch (e) {
                    root.log = String(e);
                }
            }
        }
    }
    Process {
        id: setter
        stdout: StdioCollector {
            onStreamFinished: root.log = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim())
                root.log = text.trim()
        }
        onExited: root.refresh()
    }
}
