#!/usr/bin/env python3
"""Own only Spaces' shell entries and the workspace widget it replaces."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile

PLUGIN = "tornikegomareli.spaces"
WORKSPACES = "omarchy.workspaces"
config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
config_path = config_home / "omarchy/shell.json"
journal = state_home / PLUGIN / "installation-v1.json"


def read(path, default=None):
    if not path.exists():
        return copy.deepcopy(default)
    return json.loads(path.read_text())


def write(path, value):
    # Respect dotfile managers: update a linked file's target, not its symlink.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def layout(config):
    bar = config.setdefault("bar", {})
    if bar.get("id", "omarchy.bar") != "omarchy.bar":
        raise ValueError("Spaces requires the built-in Omarchy bar")
    if "layout" not in bar:
        defaults = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "config/omarchy/shell.json"
        bar["layout"] = read(defaults)["bar"]["layout"]
    return bar["layout"]


def entries(config, ids):
    return [{"section": section, "index": i, "entry": entry}
            for section, values in layout(config).items()
            for i, entry in enumerate(values) if entry.get("id") in ids]


def remove_entries(config, ids):
    for section, values in layout(config).items():
        config["bar"]["layout"][section] = [e for e in values if e.get("id") not in ids]
    config["plugins"] = [e for e in config.get("plugins", []) if e.get("id") not in ids]
    remove_disabled(config, ids)


def remove_disabled(config, ids):
    if "disabledPlugins" in config:
        config["disabledPlugins"] = [e for e in config["disabledPlugins"] if e not in ids]
        if not config["disabledPlugins"]:
            del config["disabledPlugins"]


def restore_entries(config, saved):
    for item in saved:
        values = layout(config).setdefault(item["section"], [])
        if not any(e.get("id") == item["entry"]["id"] for e in values):
            values.insert(min(item["index"], len(values)), item["entry"])


def clean_agent_hooks():
    # Remove only this plugin's command hooks, preserving other agents/hooks.
    path = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "settings.json"
    settings = read(path, {})
    changed = False
    for event, groups in list(settings.get("hooks", {}).items()):
        remaining = []
        for group in groups:
            hooks = group.get("hooks", [])
            kept = [h for h in hooks if not (h.get("type") == "command" and
                    f"/omarchy/plugins/{PLUGIN}/hooks/claude-hook " in h.get("command", ""))]
            changed |= len(kept) != len(hooks)
            if kept or not hooks:
                remaining.append(dict(group, hooks=kept))
        if remaining:
            settings["hooks"][event] = remaining
        else:
            del settings["hooks"][event]
    if changed:
        write(path, settings)


def main(action):
    config = read(config_path, {})
    if action == "capture":
        if journal.exists():
            if read(journal).get("schemaVersion") != 1:
                raise ValueError("Unknown installation journal version")
            return
        owned = {PLUGIN, WORKSPACES}
        write(journal, {"schemaVersion": 1, "complete": False, "entries": entries(config, owned),
                       "plugins": [e for e in config.get("plugins", []) if e.get("id") in owned],
                       "disabled": [e for e in config.get("disabledPlugins", []) if e in owned]})
    elif action == "complete":
        saved = read(journal)
        saved["complete"] = True
        write(journal, saved)
    elif action == "place":
        saved = read(journal)
        existing = entries(config, {PLUGIN})
        target = next((e for e in saved["entries"] if e["entry"]["id"] == WORKSPACES), None)
        # Retain existing Spaces settings/placement, otherwise take the switcher's slot.
        remove_entries(config, {WORKSPACES})
        if not existing:
            item = dict(target, entry={"id": PLUGIN}) if target else {"section": "left", "index": 1, "entry": {"id": PLUGIN}}
            restore_entries(config, [item])
        # Native widgets are enabled by their layout presence. plugins[] is an
        # opt-in list, not an enabled/disabled map. Activate in one file write.
        remove_disabled(config, {PLUGIN})
        write(config_path, config)
    elif action in ("remove", "rollback"):
        saved = read(journal, {"entries": [], "plugins": []})
        ids = {PLUGIN, WORKSPACES} if action == "rollback" else {PLUGIN}
        remove_entries(config, ids)
        # Revert only the default switcher's override made by our installer.
        if journal.exists():
            config["plugins"] = [e for e in config["plugins"] if e.get("id") != WORKSPACES]
            keep = {PLUGIN, WORKSPACES} if action == "rollback" else {WORKSPACES}
            remove_disabled(config, keep)
            restore_entries(config, [e for e in saved["entries"] if e["entry"]["id"] in keep])
            config["plugins"].extend(e for e in saved["plugins"] if e.get("id") in keep)
            previous_disabled = [e for e in saved.get("disabled", []) if e in keep]
            if previous_disabled:
                config.setdefault("disabledPlugins", []).extend(previous_disabled)
        write(config_path, config)
        if action == "remove":
            clean_agent_hooks()
    else:
        raise ValueError("usage: installation-state.py capture|place|complete|remove|rollback")


if __name__ == "__main__":
    try:
        main(sys.argv[1] if len(sys.argv) == 2 else "")
    except (ValueError, KeyError, OSError, TypeError) as error:
        sys.exit(f"Spaces installation state: {error}")
