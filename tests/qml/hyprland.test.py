#!/usr/bin/env python3
"""Real windows + official Hyprbars in a disposable, nested Hyprland.

SPACES_TEST_HYPRBARS must name an official ABI-matched hyprbars.so.
Requires labwc, Hyprland, foot, grim and a render node. Never uses the host seat.
"""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = "tornikegomareli.spaces"
LABWC = os.environ.get("SPACES_TEST_LABWC") or shutil.which("labwc")
BACKEND = Path(os.environ["SPACES_TEST_BINARY"])
HYPRBARS = Path(os.environ["SPACES_TEST_HYPRBARS"])
assert LABWC and BACKEND.is_file() and HYPRBARS.is_file()


def wait_for(predicate, description):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(description)


# Keep the runtime path short: Hyprland's Unix IPC socket has a 108-byte limit.
with tempfile.TemporaryDirectory(prefix="sp-") as directory:
    base = Path(directory)
    artifacts = Path(os.environ.get("SPACES_UI_ARTIFACTS", base / "artifacts")).resolve()
    artifacts.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LIBSEAT_BACKEND="seatd", SEATD_SOCK=str(base / "no-seat"),
               HYPRLAND_NO_SD_NOTIFY="1", HYPRLAND_NO_SD_VARS="1",
               QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="")
    for name in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "LD_LIBRARY_PATH"):
        env.pop(name, None)
    for key, name in (("RUNTIME_DIR", "r"), ("CONFIG_HOME", "config"), ("DATA_HOME", "data"), ("STATE_HOME", "state"), ("CACHE_HOME", "cache")):
        (base / name).mkdir(mode=0o700)
        env["XDG_" + key] = str(base / name)
    binary_dir = base / "data" / PLUGIN / "bin"
    binary_dir.mkdir(parents=True)
    shutil.copy2(BACKEND, binary_dir / "spaces-backend")
    shutil.copy2(ROOT / "scripts/hyprbars-action.sh", binary_dir / "spaces-hyprbars-action")
    # The fixture loads the official .so itself. Never let a config reload run
    # the user's hyprpm registry through the titlebar's startup hook.
    (base / "bin").mkdir()
    (base / "bin/hyprpm").write_text("#!/bin/sh\nexit 0\n")
    (base / "bin/hyprpm").chmod(0o755)
    env["PATH"] = str(base / "bin") + ":" + env["PATH"]
    config = base / "config/hyprland.lua"
    config.write_text('''hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
hl.config({ animations = { enabled = false }, misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
''')
    processes = []
    logs = []

    def spawn(args, name, environment=env):
        log = (artifacts / (name + ".log")).open("w")
        logs.append(log)
        process = subprocess.Popen(args, env=environment, stdout=log, stderr=subprocess.STDOUT)
        processes.append(process)
        return process

    def output(*args):
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout.strip()

    def cli(*args):
        value = json.loads(output(str(binary_dir / "spaces-backend"), "--protocol", "6", *args))
        assert value["ok"], value
        return value

    def clients():
        return json.loads(output("hyprctl", "-j", "clients"))

    def ipc(method, *args):
        return output("qs", "ipc", "-p", str(base / "qml"), "call", "spaces-test", method, *args)

    def status():
        try:
            return json.loads(ipc("status"))
        except (AssertionError, ValueError):
            return {}

    try:
        labwc_env = dict(env, WLR_BACKENDS="headless", WLR_RENDERER="gles2", WLR_HEADLESS_OUTPUTS="1")
        if "SPACES_TEST_LABWC_LIBS" in os.environ:
            labwc_env["LD_LIBRARY_PATH"] = os.environ["SPACES_TEST_LABWC_LIBS"]
        spawn([LABWC, "-C", str(base / "config")], "labwc", labwc_env)
        wait_for(lambda: (base / "r/wayland-0").is_socket(), "labwc did not start")
        env["WAYLAND_DISPLAY"] = "wayland-0"
        spawn(["Hyprland", "--config", str(config)], "hyprland")
        socket = wait_for(lambda: next((base / "r/hypr").glob("*/.socket.sock"), None), "Hyprland IPC did not start")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = socket.parent.name
        env["WAYLAND_DISPLAY"] = "wayland-1"
        if not json.loads(output("hyprctl", "-j", "monitors")):
            output("hyprctl", "output", "create", "headless")
        wait_for(lambda: json.loads(output("hyprctl", "-j", "monitors")), "No isolated monitor")
        # Keep a keyboard on the isolated seat. Creating the very first input
        # device after a panel maps otherwise changes compositor focus itself.
        spawn(["wtype", "-s", "100000"], "virtual-keyboard")
        assert not output("hyprctl", "configerrors")
        output("hyprctl", "plugin", "load", str(HYPRBARS))
        config.write_text(config.read_text() + "\ndofile(" + json.dumps(str(ROOT / "hyprbars/spaces-hyprbars.lua")) + ")\n")
        output("hyprctl", "reload")
        assert not output("hyprctl", "configerrors")
        assert "hyprbars" in output("hyprctl", "plugin", "list")
        for i in range(3):
            spawn(["foot", "--app-id=foot", "--title=Spaces acceptance " + str(i), "sleep", "180"], "foot-" + str(i))
        rows = wait_for(lambda: clients() if len(clients()) == 3 else None, "Three real windows did not map")
        addresses = [row["address"] for row in rows]
        for address in addresses:
            cli("window-action", "move-workspace", address, "3")
        cli("window-action", "focus", addresses[0])
        qml = base / "qml"
        qml.mkdir()
        host = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
        for module in ("Commons", "Ui"):
            (qml / module).symlink_to(host / module, target_is_directory=True)
        (qml / "plugin").symlink_to(ROOT, target_is_directory=True)
        (qml / "upstream").mkdir()
        for filename in ("Spaces.qml", "Model.js"):
            (qml / "upstream" / filename).write_bytes(subprocess.check_output(["git", "-C", str(ROOT), "show", "f8306d7:" + filename]))
        (base / "bin/omarchy-shell").write_text("#!/bin/sh\nexec qs ipc -p " + shlex.quote(str(qml)) + ' call "$@"\n')
        (base / "bin/omarchy-shell").chmod(0o755)
        env["SPACES_UI_ARTIFACTS"] = str(artifacts)
        shutil.copy(ROOT / "tests/qml/live.qml", qml / "shell.qml")
        widget = spawn(["qs", "-p", str(qml), "--no-color"], "quickshell")
        wait_for(lambda: status().get("backendHealthy") and status().get("projected") == 3, "Real service/workspace model did not load")
        assert status()["workspace"] == 3
        output("grim", str(artifacts / "hyprbars.png"))
        ipc("desktopClick")
        wait_for(lambda: status().get("minimized") == 3 and not status().get("batchBusy"), "Corner strip did not hide workspace")
        ipc("desktopClick")
        wait_for(lambda: status().get("minimized") == 0 and not status().get("batchBusy"), "Corner strip did not restore workspace")
        for name, settings in (("default", {}), ("expanded", {"showApps": "all"}),
                               ("grouped", {"showApps": "all", "groupApps": True, "focusedTitle": True})):
            ipc("compare", name, json.dumps(dict(settings, animations=False)))
            wait_for(lambda: status().get("comparisonDone"), "Visual comparison did not finish")
            comparison = subprocess.run(["magick", "compare", "-metric", "AE",
                str(artifacts / ("upstream-" + name + ".png")), str(artifacts / ("fork-" + name + ".png")),
                str(artifacts / ("diff-" + name + ".png"))], capture_output=True, text=True)
            assert comparison.returncode == 0, "Visual drift from upstream: " + name + " " + comparison.stderr
        print("Upstream pixel comparison passed: default, expanded and grouped/title pills.")
        assert ipc("minimize", addresses[0]) == "true"
        wait_for(lambda: status().get("minimized") == 1 and not status().get("batchBusy"), "QML minimize did not complete")
        assert status()["projected"] == 3
        widget.terminate()
        widget.wait(timeout=5)
        widget = spawn(["qs", "-p", str(qml), "--no-color"], "quickshell-restarted")
        wait_for(lambda: status().get("backendHealthy") and status().get("minimized") == 1 and status().get("projected") == 3,
                 "Restart lost the minimized window or its original workspace")
        assert ipc("restore", addresses[0]) == "true"
        wait_for(lambda: status().get("minimized") == 0, "QML restore did not complete")
        for _ in range(2):
            ipc("openMenu", addresses[0])
            wait_for(lambda: status().get("menuFocus"), "Native menu keyboard focus failed")
            output("wtype", "-s", "150", "-k", "Down", "-s", "80", "-k", "Escape")
            wait_for(lambda: not status().get("menuOpen"), "Native menu Escape failed")
        ipc("preview", "3")
        wait_for(lambda: status().get("previewOpen"), "Live preview did not open")
        time.sleep(0.5)
        output("grim", str(artifacts / "live-preview.png"))
        # The real titlebar helper delegates into the real transactional helper.
        output(str(binary_dir / "spaces-hyprbars-action"), "minimize")
        assert len(cli("snapshot")["minimized"]) == 1
        cli("restore", addresses[0], "--focus")
        output(str(binary_dir / "spaces-hyprbars-action"), "maximize")
        assert next(c for c in clients() if c["address"] == addresses[0])["fullscreen"] == 1
        output(str(binary_dir / "spaces-hyprbars-action"), "maximize")
        cli("minimize", addresses[0])
        cli("show-desktop-toggle", "3")
        assert len(cli("snapshot")["minimized"]) == 3
        cli("show-desktop-toggle", "3")
        assert [r["address"] for r in cli("snapshot")["minimized"]] == [addresses[0]]
        cli("restore-workspace", "3")
        cli("window-action", "pop-toggle", addresses[0])
        popped = next(c for c in clients() if c["address"] == addresses[0])
        assert popped["floating"] and popped["pinned"]
        cli("window-action", "pop-toggle", addresses[0])
        cli("window-action", "move-workspace", addresses[0], "special:scratchpad")
        cli("minimize", addresses[0])
        cli("restore", addresses[0])
        assert next(c for c in clients() if c["address"] == addresses[0])["workspace"]["name"] == "special:scratchpad"
        cli("recover")
        assert cli("doctor-json")["records"] == 0
        before = {m["name"] for m in json.loads(output("hyprctl", "-j", "monitors"))}
        output("hyprctl", "output", "create", "headless")
        second = wait_for(lambda: next((m for m in json.loads(output("hyprctl", "-j", "monitors")) if m["name"] not in before), None), "Second monitor missing")
        config.write_text(config.read_text() + '\nhl.monitor({ output = ' + json.dumps(second["name"]) + ', mode = "1600x900@60", position = "1280x0", scale = 1.25 })\n')
        output("hyprctl", "reload")
        assert not output("hyprctl", "configerrors")
        cli("window-action", "move-monitor", addresses[1], second["name"])
        cli("minimize", addresses[1])
        record = cli("snapshot")["minimized"][0]
        assert record["monitor_id"] == second["id"], record
        cli("restore", addresses[1])
        assert next(c for c in clients() if c["address"] == addresses[1])["monitor"] == second["id"]
        cli("minimize", addresses[1])
        output("hyprctl", "output", "remove", second["name"])
        cli("recover")
        assert cli("doctor-json")["records"] == 0
        widget.terminate()
        widget.wait(timeout=5)
        qml_log = (artifacts / "quickshell.log").read_text() + (artifacts / "quickshell-restarted.log").read_text()
        assert not any(error in qml_log for error in ("TypeError", "ReferenceError", "Binding loop", "Unable to assign")), qml_log
        # Reload our real Lua twice: no duplicate buttons/rules/config errors.
        output("hyprctl", "reload")
        output("hyprctl", "reload")
        assert not output("hyprctl", "configerrors")
        config.write_text(config.read_text().split("\ndofile(")[0])
        output("hyprctl", "reload")
        output("hyprctl", "plugin", "unload", str(HYPRBARS))
        assert not output("hyprctl", "configerrors")
        assert "hyprbars" not in output("hyprctl", "plugin", "list")
        print("Real Hyprland + official Hyprbars: load/reload/unload, QML service/restart, native menu focus/reopen, live preview, minimize/restore, maximize, desktop batches, Pop, scratchpad, two monitors, monitor removal and recovery passed.")
        if "SPACES_UI_ARTIFACTS" in os.environ:
            print(f"Artifacts: {artifacts}")
    finally:
        for log_path in (base / "r/hypr").glob("*/hyprland.log"):
            shutil.copy(log_path, artifacts / "hyprland-internal.log")
        for process in reversed(processes):
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for log in logs:
            log.close()
