#!/usr/bin/env python3
"""Resolve desktop actions without interpolating user paths into a shell."""
import argparse
import configparser
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile

# (command, label, runs in a terminal, app-id of its window). Terminal monitors
# get TASKMGR_ID as their terminal's app-id, so niri can float them.
TASKMGR_ID = "angelos.taskmgr"
MONITORS = [
    ("btop", "btop", True, TASKMGR_ID),
    ("missioncenter", "Mission Center", False, "io.missioncenter.MissionCenter"),
    ("resources", "Resources", False, "net.nokyan.Resources"),
    ("gnome-system-monitor", "GNOME System Monitor", False, "gnome-system-monitor|org.gnome.SystemMonitor"),
    ("plasma-systemmonitor", "Plasma System Monitor", False, "org.kde.plasma-systemmonitor|org.kde.plasmasystemmonitor"),
    ("xfce4-taskmanager", "Xfce Task Manager", False, "xfce4-taskmanager"),
    ("lxtask", "LXTask", False, "lxtask"),
    ("htop", "htop", True, TASKMGR_ID),
    ("top", "top", True, TASKMGR_ID),
]
DIRECTORIES = {"HOME", "DOWNLOAD", "DOCUMENTS", "PICTURES", "MUSIC", "VIDEOS", "DESKTOP"}


def monitors():
    return [{"value": cmd, "label": label, "terminal": terminal, "appId": app_id}
            for cmd, label, terminal, app_id in MONITORS if shutil.which(cmd)]


def directory(kind):
    if kind not in DIRECTORIES:
        raise ValueError("Unknown user directory")
    if kind == "HOME":
        return str(Path.home())
    result = subprocess.run(["xdg-user-dir", kind], capture_output=True, text=True, check=True)
    path = Path(result.stdout.strip())
    if not path.is_absolute() or not path.is_dir():
        raise ValueError("User directory does not exist: " + str(path))
    return str(path)


def new_text():
    fd, path = tempfile.mkstemp(prefix="kukabara-note-", suffix=".txt")
    os.close(fd)
    return path


def default_editor():
    result = subprocess.run(["xdg-mime", "query", "default", "text/plain"],
                            capture_output=True, text=True, check=True)
    desktop_id = result.stdout.strip()
    if not desktop_id:
        return None
    data_home = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))
    roots = [data_home] + os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    for root in roots:
        applications = Path(root) / "applications"
        direct = applications / desktop_id
        # Desktop IDs flatten subdirectory names with '-' (e.g. kde-foo.desktop).
        candidates = [direct] if direct.is_file() else [
            p for p in applications.rglob("*.desktop")
            if str(p.relative_to(applications)).replace("/", "-") == desktop_id
        ]
        for path in candidates:
            entry = configparser.ConfigParser(interpolation=None, strict=False)
            entry.read(path)
            return path, entry["Desktop Entry"]
    return None


def open_text_argv(path, terminal):
    # Empty .txt files are detected as inode/x-empty. Resolve text/plain explicitly.
    editor = default_editor()
    if editor is None:
        return ["xdg-open", str(path)]
    desktop_path, entry = editor
    if not entry.getboolean("Terminal", fallback=False):
        return ["gio", "launch", str(desktop_path), str(path)]
    argv = []
    has_file = False
    for token in shlex.split(entry.get("Exec", "")):
        if token in ("%f", "%F", "%u", "%U"):
            argv.append(Path(path).as_uri() if token in ("%u", "%U") else str(path))
            has_file = True
        elif token == "%i":
            if entry.get("Icon"):
                argv.extend(["--icon", entry["Icon"]])
        elif token == "%c":
            argv.append(entry.get("Name", "Text editor"))
        elif token == "%k":
            argv.append(str(desktop_path))
        elif not token.startswith("%") or token == "%%":
            argv.append(token.replace("%%", "%"))
    if not argv:
        raise ValueError("Default text editor has no executable")
    if not has_file:
        argv.append(str(path))
    name = Path(terminal).name
    if name in ("kitty", "foot"):
        return [terminal] + argv
    if name == "wezterm":
        return [terminal, "start", "--"] + argv
    return [terminal, "-e"] + argv


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["monitors", "directory", "text"])
    parser.add_argument("kind", nargs="?")
    parser.add_argument("--resolve-only", action="store_true")
    parser.add_argument("--terminal", default="kitty")
    args = parser.parse_args()
    if args.action == "monitors":
        print(json.dumps(monitors()))
        return
    path = directory(args.kind) if args.action == "directory" else new_text()
    print(path, flush=True)
    if not args.resolve_only:
        argv = open_text_argv(path, args.terminal) if args.action == "text" else ["xdg-open", path]
        subprocess.Popen(argv, start_new_session=True)


if __name__ == "__main__":
    main()
