"""kukabara for Nautilus: «Открыть в терминале» with the terminal chosen in kukabara.

Installed by kukabara (Settings → Default apps → Files · Nautilus). The terminal
comes from ~/.config/angelos/settings.json (system.terminal) at click time.
"""
import json
import os
import shutil
import subprocess
from typing import List
from urllib.parse import unquote

from gi.repository import GObject, Nautilus

SETTINGS = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "angelos/settings.json")


def terminal():
    try:
        with open(SETTINGS, encoding="utf-8") as stream:
            name = (json.load(stream).get("system") or {}).get("terminal") or ""
    except (OSError, ValueError, AttributeError):
        name = ""
    # Nautilus may run with a PATH that lacks ~/.local/bin, where terminal wrappers live
    search = os.environ.get("PATH", "") + os.pathsep + os.path.expanduser("~/.local/bin")
    for candidate in (name, "kitty", "foot", "alacritty", "wezterm", "gnome-terminal", "konsole", "xterm"):
        found = candidate and shutil.which(os.path.expanduser(candidate), path=search)
        if found:
            return found
    return None


def argv_in(term, folder):
    base = os.path.basename(term)
    if base == "kitty":
        return [term, "--working-directory", folder]
    if base == "foot":
        return [term, "--working-directory", folder]
    if base == "alacritty":
        return [term, "--working-directory", folder]
    if base == "wezterm":
        return [term, "start", "--cwd", folder]
    if base == "gnome-terminal":
        return [term, "--working-directory=" + folder]
    if base == "konsole":
        return [term, "--workdir", folder]
    return [term]


class AngelosOpenTerminal(GObject.GObject, Nautilus.MenuProvider):
    @staticmethod
    def folder(file):
        uri = file.get_uri()
        path = unquote(uri[7:]) if uri.startswith("file://") else ""
        if path and not file.is_directory():
            path = os.path.dirname(path)
        return path if path and os.path.isdir(path) else os.path.expanduser("~")

    def open(self, _menu, file):
        term = terminal()
        if not term:
            return
        folder = self.folder(file)
        subprocess.Popen(argv_in(term, folder), cwd=folder, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def item(self, name, file):
        item = Nautilus.MenuItem(name="AngelosOpenTerminal::" + name, label="Открыть в терминале")
        item.connect("activate", self.open, file)
        return [item]

    def get_file_items(self, files: List[Nautilus.FileInfo]):
        if len(files) != 1 or files[0].get_uri_scheme() != "file":
            return []
        return self.item("file", files[0])

    def get_background_items(self, folder: Nautilus.FileInfo):
        if folder.get_uri_scheme() != "file":
            return []
        return self.item("background", folder)
