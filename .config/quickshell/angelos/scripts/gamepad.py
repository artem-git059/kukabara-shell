#!/usr/bin/env python3
"""Gamepad tester backend for kukabara (Settings → Gamepad). Runs only while that
page is open. Devices are read, never grabbed, so games keep working.

stdout (JSON lines):
  {"event": "devices", "list": [{id, name, vendor, product, ff, buttons, axes, battery}]}
  {"event": "state", "id", "keys": [...], "abs": {code: value}}      full snapshot
  {"event": "key", "id", "code", "value"}                              0 / 1 / 2 (repeat)
  {"event": "abs", "id", "values": {code: value}}                      ~60 Hz, sticks -1..1, triggers 0..1, hats -1/0/1
stdin (JSON lines):
  {"cmd": "rumble", "id", "strong": 0..1, "weak": 0..1, "ms": 1..3000}
  {"cmd": "snapshot", "id"}
"""
import json
import os
from pathlib import Path
import selectors
import sys
import time

import evdev
from evdev import ecodes

sel = selectors.DefaultSelector()
devices = {}        # path -> {"dev", "id", "abs", "info"}
pending = {}        # id -> {code: value} not yet sent
effects = {}        # id -> uploaded rumble effect id


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


PREFERRED = ("BTN_SOUTH", "BTN_EAST", "BTN_NORTH", "BTN_WEST", "BTN_C", "BTN_Z", "BTN_TRIGGER", "BTN_THUMB")


def code_name(kind, code):
    """One stable name per code (the kernel lists aliases such as BTN_A/BTN_SOUTH)."""
    names = (ecodes.BTN if kind == ecodes.EV_KEY else ecodes.ABS)
    n = names.get(code) or ecodes.KEY.get(code) or str(code)
    if isinstance(n, (list, tuple)):
        return next((x for x in PREFERRED if x in n), n[0])
    return n


def is_pad(dev):
    keys = dev.capabilities().get(ecodes.EV_KEY, [])
    return any(k in keys for k in (ecodes.BTN_SOUTH, ecodes.BTN_GAMEPAD, ecodes.BTN_JOYSTICK, ecodes.BTN_TRIGGER))


def normalize(info, value):
    lo, hi = info.min, info.max
    if hi <= lo:
        return 0
    if lo < 0 or (lo == 0 and hi > 1 and info.flat > 0):   # centred axis (sticks)
        mid = (lo + hi) / 2
        v = (value - mid) / ((hi - lo) / 2)
    elif hi - lo <= 2:                                      # hats: -1 / 0 / 1
        return value
    else:                                                   # triggers 0..max
        v = (value - lo) / (hi - lo)
    return round(max(-1.0, min(1.0, v)), 4)


def batteries():
    out = []
    for ps in Path("/sys/class/power_supply").glob("*"):
        try:
            if (ps / "scope").read_text().strip().lower() != "device":
                continue
            out.append({"name": ps.name, "capacity": int((ps / "capacity").read_text().strip())})
        except (OSError, ValueError):
            continue
    return out


def describe(entry):
    dev = entry["dev"]
    try:
        caps = dev.capabilities(absinfo=True)
    except OSError:
        return {"id": entry["id"], "name": "?", "vendor": "0000", "product": "0000", "ff": False, "buttons": [], "axes": []}
    axes = [{"code": code_name(ecodes.EV_ABS, c), "min": i.min, "max": i.max, "flat": i.flat}
            for c, i in caps.get(ecodes.EV_ABS, [])]
    return {"id": entry["id"], "name": dev.name, "vendor": "%04x" % dev.info.vendor,
            "product": "%04x" % dev.info.product, "ff": ecodes.EV_FF in caps,
            "buttons": [code_name(ecodes.EV_KEY, c) for c in caps.get(ecodes.EV_KEY, [])], "axes": axes}


def snapshot(entry):
    dev = entry["dev"]
    try:
        keys = [code_name(ecodes.EV_KEY, c) for c in dev.active_keys()]
        values = {code_name(ecodes.EV_ABS, c): normalize(i, dev.absinfo(c).value) for c, i in entry["abs"].items()}
    except OSError:
        return
    emit({"event": "state", "id": entry["id"], "keys": keys, "abs": values})


def rescan():
    changed = False
    present = set(evdev.list_devices())
    for path in list(devices):
        if path not in present:
            drop(path)
            changed = True
    for path in present:
        if path in devices:
            continue
        try:
            dev = evdev.InputDevice(path)
            if not is_pad(dev):
                dev.close()
                continue
            abs_info = dict(dev.capabilities(absinfo=True).get(ecodes.EV_ABS, []))
        except OSError:
            continue
        entry = {"dev": dev, "id": Path(path).name, "abs": abs_info}
        devices[path] = entry
        sel.register(dev.fd, selectors.EVENT_READ, path)
        changed = True
    if changed:
        emit({"event": "devices", "list": [describe(e) for e in devices.values()], "batteries": batteries()})
        for e in devices.values():
            snapshot(e)


def drop(path):
    entry = devices.pop(path, None)
    if not entry:
        return
    try:
        sel.unregister(entry["dev"].fd)
    except (KeyError, ValueError):
        pass
    effects.pop(entry["id"], None)
    try:
        entry["dev"].close()
    except OSError:
        pass


def rumble(msg):
    entry = next((e for e in devices.values() if e["id"] == msg.get("id")), None)
    if not entry or ecodes.EV_FF not in entry["dev"].capabilities():
        return
    dev = entry["dev"]
    ms = max(1, min(3000, int(msg.get("ms", 400))))
    strong = int(max(0.0, min(1.0, float(msg.get("strong", 0.8)))) * 0xFFFF)
    weak = int(max(0.0, min(1.0, float(msg.get("weak", 0.5)))) * 0xFFFF)
    try:
        effect = evdev.ff.Effect(ecodes.FF_RUMBLE, -1, 0, evdev.ff.Trigger(0, 0), evdev.ff.Replay(ms, 0),
                                 evdev.ff.EffectType(ff_rumble_effect=evdev.ff.Rumble(strong_magnitude=strong, weak_magnitude=weak)))
        old = effects.pop(entry["id"], None)
        if old is not None:
            try:
                dev.erase_effect(old)
            except OSError:
                pass
        eid = dev.upload_effect(effect)
        effects[entry["id"]] = eid
        dev.write(ecodes.EV_FF, eid, 1)
    except (OSError, AttributeError) as error:
        emit({"event": "error", "message": "rumble: " + str(error)})


def on_stdin():
    line = sys.stdin.readline()
    if not line:
        raise SystemExit(0)
    try:
        msg = json.loads(line)
    except ValueError:
        return
    if msg.get("cmd") == "rumble":
        rumble(msg)
    elif msg.get("cmd") == "snapshot":
        for e in devices.values():
            if e["id"] == msg.get("id"):
                snapshot(e)


def main():
    os.set_blocking(sys.stdin.fileno(), True)
    sel.register(sys.stdin, selectors.EVENT_READ, "stdin")
    rescan()
    last_scan = last_flush = time.monotonic()
    while True:
        for key, _ in sel.select(timeout=0.016):
            if key.data == "stdin":
                on_stdin()
                continue
            entry = devices.get(key.data)
            if not entry:
                continue
            try:
                for ev in entry["dev"].read():
                    if ev.type == ecodes.EV_KEY:
                        emit({"event": "key", "id": entry["id"], "code": code_name(ecodes.EV_KEY, ev.code), "value": ev.value})
                    elif ev.type == ecodes.EV_ABS and ev.code in entry["abs"]:
                        pending.setdefault(entry["id"], {})[code_name(ecodes.EV_ABS, ev.code)] = normalize(entry["abs"][ev.code], ev.value)
            except BlockingIOError:
                pass
            except OSError:
                drop(key.data)
                emit({"event": "devices", "list": [describe(e) for e in devices.values()], "batteries": batteries()})
        now = time.monotonic()
        if pending and now - last_flush >= 0.016:
            for did, values in pending.items():
                emit({"event": "abs", "id": did, "values": values})
            pending.clear()
            last_flush = now
        if now - last_scan >= 2:
            rescan()
            last_scan = now


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError, SystemExit):
        pass
