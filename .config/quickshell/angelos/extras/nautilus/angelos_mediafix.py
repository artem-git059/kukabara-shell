"""kukabara for Nautilus: videos → «Подготовить для DaVinci Resolve (mediafix)».

Runs the mediafix bundled with kukabara in the terminal chosen in kukabara; the
selected files are passed as arguments, never through a shell.
"""
import os
import subprocess
from typing import List
from urllib.parse import unquote

from gi.repository import GObject, Nautilus

SHELL_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "quickshell/angelos")
SETUP = os.path.join(SHELL_DIR, "scripts/nautilus-setup.py")
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".mxf", ".webm", ".ts", ".mts", ".m2ts",
                    ".flv", ".wmv", ".mpg", ".mpeg", ".m4v", ".3gp"}


class AngelosMediafix(GObject.GObject, Nautilus.MenuProvider):
    @staticmethod
    def path(file):
        uri = file.get_uri()
        return unquote(uri[7:]) if uri.startswith("file://") else ""

    def run(self, _menu, files):
        paths = [p for p in (self.path(f) for f in files) if p]
        if paths:
            subprocess.Popen(["python3", SETUP, "mediafix", *paths], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def get_file_items(self, files: List[Nautilus.FileInfo]):
        if not files or any(f.get_uri_scheme() != "file" or f.is_directory() for f in files):
            return []
        if any(os.path.splitext(self.path(f))[1].lower() not in VIDEO_EXTENSIONS for f in files):
            return []
        item = Nautilus.MenuItem(name="AngelosMediafix::prepare",
                                 label="Подготовить для DaVinci Resolve (mediafix)")
        item.connect("activate", self.run, files)
        return [item]
