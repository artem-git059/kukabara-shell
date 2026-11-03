#!/usr/bin/env python3
"""BlueZ pairing agent for kukabara (org.bluez.Agent1, capability KeyboardDisplay).

Questions go to stdout as JSON lines:
  {"event": "request", "id": N, "kind": "confirm|pin|passkey|authorize|display", "device": "...", "passkey": "..."}
kukabara answers on stdin:
  {"id": N, "ok": true|false, "pin": "..."}
Unanswered questions are rejected after 60 s. The agent registers as the default
agent while it runs and unregisters on exit.
"""
import json
import signal
import sys
import warnings

from gi.repository import Gio, GLib

warnings.simplefilter("ignore", DeprecationWarning)   # register_object: the closure API is not in every PyGObject

AGENT_PATH = "/org/angelos/BluetoothAgent"
XML = """<node><interface name="org.bluez.Agent1">
<method name="Release"/>
<method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
<method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
<method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
<method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
<method name="RequestAuthorization"><arg type="o" direction="in"/></method>
<method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="Cancel"/>
</interface></node>"""

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
pending = {}
counter = [0]


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def device_name(path):
    try:
        props = bus.call_sync("org.bluez", path, "org.freedesktop.DBus.Properties", "GetAll",
                              GLib.Variant("(s)", ("org.bluez.Device1",)), None, Gio.DBusCallFlags.NONE, 2000, None)
        values = props.unpack()[0]
        return str(values.get("Alias") or values.get("Name") or values.get("Address") or path)
    except GLib.Error:
        return path


def reject(invocation, text="Rejected"):
    invocation.return_dbus_error("org.bluez.Error.Rejected", text)


def ask(invocation, kind, device, passkey=""):
    counter[0] += 1
    rid = counter[0]
    timeout = GLib.timeout_add_seconds(60, lambda: finish(rid, False, expired=True) or False)
    pending[rid] = (invocation, kind, timeout)
    emit({"event": "request", "id": rid, "kind": kind, "device": device_name(device), "passkey": passkey})


def finish(rid, ok, pin="", expired=False):
    entry = pending.pop(rid, None)
    if not entry:
        return
    invocation, kind, timeout = entry
    if not expired:
        GLib.source_remove(timeout)
    if not ok:
        reject(invocation)
        emit({"event": "cancel", "id": rid})
        return
    if kind == "pin":
        pin = str(pin)[:16]
        if not pin:
            return reject(invocation)
        invocation.return_value(GLib.Variant("(s)", (pin,)))
    elif kind == "passkey":
        digits = "".join(c for c in str(pin) if c.isdigit())[:6]
        if not digits:
            return reject(invocation)
        invocation.return_value(GLib.Variant("(u)", (int(digits),)))
    else:
        invocation.return_value(None)


def on_call(_conn, _sender, _path, _iface, method, params, invocation):
    args = params.unpack()
    if method == "RequestConfirmation":
        ask(invocation, "confirm", args[0], "%06d" % args[1])
    elif method == "RequestPinCode":
        ask(invocation, "pin", args[0])
    elif method == "RequestPasskey":
        ask(invocation, "passkey", args[0])
    elif method in ("RequestAuthorization", "AuthorizeService"):
        ask(invocation, "authorize", args[0])
    elif method == "DisplayPinCode":
        emit({"event": "request", "id": 0, "kind": "display", "device": device_name(args[0]), "passkey": str(args[1])})
        invocation.return_value(None)
    elif method == "DisplayPasskey":
        emit({"event": "request", "id": 0, "kind": "display", "device": device_name(args[0]), "passkey": "%06d" % args[1]})
        invocation.return_value(None)
    elif method == "Cancel":
        for rid in list(pending):
            finish(rid, False)
        invocation.return_value(None)
    else:  # Release
        invocation.return_value(None)


def on_stdin(channel, condition):
    if condition & (GLib.IO_HUP | GLib.IO_ERR):
        loop.quit()
        return False
    line = channel.readline()
    if not line:
        loop.quit()
        return False
    try:
        msg = json.loads(line)
        finish(int(msg.get("id", 0)), bool(msg.get("ok")), msg.get("pin", ""))
    except (ValueError, TypeError):
        pass
    return True


def manager(method, *args):
    sig = "(os)" if method == "RegisterAgent" else "(o)"
    bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", method,
                  GLib.Variant(sig, args), None, Gio.DBusCallFlags.NONE, 5000, None)


loop = GLib.MainLoop()
node = Gio.DBusNodeInfo.new_for_xml(XML)
reg = bus.register_object(AGENT_PATH, node.interfaces[0], on_call, None, None)
try:
    manager("RegisterAgent", AGENT_PATH, "KeyboardDisplay")
    manager("RequestDefaultAgent", AGENT_PATH)
except GLib.Error as error:
    emit({"event": "error", "message": error.message})
    sys.exit(1)
GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.PRIORITY_DEFAULT,
                  GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
for sig in (signal.SIGTERM, signal.SIGINT):
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: loop.quit() or False)
emit({"event": "ready"})
try:
    loop.run()
finally:
    try:
        manager("UnregisterAgent", AGENT_PATH)
    except GLib.Error:
        pass
    bus.unregister_object(reg)
