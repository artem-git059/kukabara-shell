#!/usr/bin/env python3
"""Add/remove the kukabara pulse hooks in ~/.claude/settings.json.

  install-hooks.py install | uninstall | status

The settings file is copied into a new timestamped backup folder before any change.
Only entries whose command points at .../claude-companion/hooks/pulse.py are touched.
"""
import json
import shutil
import sys
import time
from pathlib import Path

SETTINGS = Path.home() / ".claude/settings.json"
HOOK = Path(__file__).resolve().parent / "pulse.py"
MARK = "claude-companion/hooks/pulse.py"
EVENTS = {
    "SessionStart": "idle",
    "UserPromptSubmit": "turn_start",
    "PreToolUse": "tool_start",
    "PostToolUse": "turn_start",
    "Notification": "needs_attention",
    "Stop": "turn_end",
    "SessionEnd": "session_end",
}


def load():
    return json.loads(SETTINGS.read_text()) if SETTINGS.exists() else {}


def strip(data):
    hooks = data.get("hooks", {})
    for ev in list(hooks):
        groups = []
        for g in hooks[ev]:
            g = dict(g)
            g["hooks"] = [h for h in g.get("hooks", []) if MARK not in h.get("command", "")]
            if g["hooks"]:
                groups.append(g)
        if groups:
            hooks[ev] = groups
        else:
            del hooks[ev]
    if not hooks:
        data.pop("hooks", None)
    return data


def backup():
    dst = Path.home() / ".local/state/angelos/backups" / (time.strftime("%Y%m%d-%H%M%S") + "-claude-settings")
    n = 1
    while dst.exists():
        n += 1
        dst = dst.with_name(dst.name.split("-claude-settings")[0] + f"-claude-settings-{n}")
    dst.mkdir(parents=True)
    if SETTINGS.exists():
        shutil.copy2(SETTINGS, dst / "settings.json")
    return dst


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    data = load()
    installed = MARK in json.dumps(data.get("hooks", {}))
    if cmd == "status":
        print("installed" if installed else "not-installed")
        return
    b = backup()
    data = strip(data)
    if cmd == "install":
        hooks = data.setdefault("hooks", {})
        for ev, pulse in EVENTS.items():
            hooks.setdefault(ev, []).append({"matcher": "*", "hooks": [{"type": "command", "command": f"python3 {HOOK} {pulse}"}]})
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS.with_suffix(".json.angelos-tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(SETTINGS)
    print(("хуки подключены" if cmd == "install" else "хуки убраны") + f" (бэкап: {b})")


if __name__ == "__main__":
    main()
