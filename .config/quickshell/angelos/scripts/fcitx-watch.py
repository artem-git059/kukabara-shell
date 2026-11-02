#!/usr/bin/env python3
"""The fcitx5 input method, for the bar's layout widget (services/Fcitx, bar/parts/KbLayout).

niri knows only its own xkb layouts; when fcitx5 runs the layouts live in it, and this reads
them over its DBus controller (org.fcitx.Fcitx5, /controller, org.fcitx.Fcitx.Controller1).
JSON lines go to stdout:
  {"available": false, "installed": true}                       fcitx5 not running (yet)
  {"available": true, "current": "keyboard-ru", "name": "Русская",
   "label": "ru", "count": 2, "ims": ["keyboard-us", "keyboard-ru"]}
Commands come on stdin, one per line: `next` / `prev` switch the input method in the current
group (SetCurrentIM), the way the tray icon's layout switch does.

fcitx5 has no signal for "the input method changed" (its controller announces only group
changes), so the state is looked at a few times a second while the daemon runs. With fcitx5
not installed at all the helper exits at once and the shell stops starting it.
"""
import json
import shutil
import sys
import threading

from gi.repository import Gio, GLib

SERVICE = "org.fcitx.Fcitx5"
PATH = "/controller"
IFACE = "org.fcitx.Fcitx.Controller1"

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
available = False
entries = []          # [(unique_name, name, label), …] of the current group
last = None           # the last line printed
timer = None


def emit(obj):
    global last
    line = json.dumps(obj, ensure_ascii=False)
    if line != last:
        last = line
        print(line, flush=True)


def call(method, args=None, reply=None):
    return bus.call_sync(SERVICE, PATH, IFACE, method, args, reply,
                         Gio.DBusCallFlags.NONE, 1000, None)


def read():
    """Current input method and its group; None when fcitx5 cannot be asked."""
    global entries
    cur = call("CurrentInputMethod", None, GLib.VariantType.new("(s)")).unpack()[0]
    group = call("FullInputMethodGroupInfo", GLib.Variant("(s)", ("",)),
                 GLib.VariantType.new("(sssa{sv}a(sssssssbsa{sv}))")).unpack()
    found = []
    for entry in group[4]:
        # unique name, localized name, native name, icon, label, language, addon, …
        found.append((str(entry[0]), str(entry[1]), str(entry[4])))
    entries = found
    name = label = ""
    for unique, long_name, short in found:
        if unique == cur:
            name, label = long_name, short
            break
    return {"available": True, "current": str(cur), "name": name, "label": label,
            "count": len(found), "ims": [e[0] for e in found]}


def tick():
    if not available:
        return False
    try:
        emit(read())
    except GLib.Error:
        # the daemon went away, or it has no dbus addon: nothing to show until it is back
        emit({"available": False, "installed": True})
    return True


def switch(step):
    if not available or len(entries) < 2:
        return
    try:
        cur = call("CurrentInputMethod", None, GLib.VariantType.new("(s)")).unpack()[0]
        names = [e[0] for e in entries]
        i = names.index(cur) if cur in names else 0
        target = names[(i + step) % len(names)]
        call("SetCurrentIM", GLib.Variant("(s)", (target,)), None)
    except (GLib.Error, ValueError):
        return
    tick()


def on_command(cmd):
    if cmd == "next":
        switch(1)
    elif cmd == "prev":
        switch(-1)
    return False


def stdin_loop():
    for line in sys.stdin:
        cmd = line.strip()
        if cmd:
            GLib.idle_add(on_command, cmd)


def appeared(_bus, _name, _owner):
    global available, timer
    available = True
    tick()
    timer = GLib.timeout_add(750, tick)


def vanished(_bus, _name):
    global available, timer
    available = False
    if timer is not None:
        GLib.source_remove(timer)
        timer = None
    emit({"available": False, "installed": True})


def main():
    if shutil.which("fcitx5") is None:
        emit({"available": False, "installed": False})
        return
    emit({"available": False, "installed": True})
    threading.Thread(target=stdin_loop, daemon=True).start()
    Gio.bus_watch_name(Gio.BusType.SESSION, SERVICE, Gio.BusNameWatcherFlags.NONE,
                       appeared, vanished)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
