#!/usr/bin/env python3
"""Render Spaces and exercise real keyboard focus in an isolated Wayland session.

Requires Omarchy shell components, qs, wtype and labwc (SPACES_TEST_LABWC can
point to a local binary). Never connects to the user's compositor. Set
SPACES_UI_ARTIFACTS to retain the screenshots and logs outside the source tree.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HOST = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
LABWC = os.environ.get("SPACES_TEST_LABWC") or shutil.which("labwc")
assert LABWC and (HOST / "Ui").is_dir(), "Omarchy and labwc are required"
assert shutil.which("wtype") and shutil.which("qs"), "qs and wtype are required"

with tempfile.TemporaryDirectory(prefix="spaces-ui-") as directory:
    base = Path(directory)
    (base / "plugin").symlink_to(ROOT, target_is_directory=True)
    for module in ("Commons", "Ui"):
        (base / module).symlink_to(HOST / module, target_is_directory=True)
    shutil.copy(Path(__file__).with_name("ui.qml"), base / "shell.qml")
    artifacts = Path(os.environ.get("SPACES_UI_ARTIFACTS", base / "artifacts")).resolve()
    artifacts.mkdir(parents=True, exist_ok=True)
    for part in ("runtime", "config", "data", "state", "cache"):
        (base / part).mkdir(mode=0o700)
    env = dict(os.environ, WLR_BACKENDS="headless", WLR_RENDERER="pixman",
               WLR_HEADLESS_OUTPUTS="1", QT_QPA_PLATFORM="wayland",
               QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software",
               SPACES_UI_ARTIFACTS=str(artifacts))
    for variable in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
        env.pop(variable, None)
    for part in ("RUNTIME", "CONFIG", "DATA", "STATE", "CACHE"):
        env[f"XDG_{part}_{'DIR' if part == 'RUNTIME' else 'HOME'}"] = str(base / part.lower())
    with (artifacts / "compositor.log").open("w") as log:
        compositor = subprocess.Popen([LABWC, "-C", str(base / "config")], env=env,
                                      stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            sockets = []
            while not sockets and time.monotonic() < deadline and compositor.poll() is None:
                sockets = [p for p in (base / "runtime").glob("wayland-*") if p.is_socket()]
                time.sleep(0.05)
            assert sockets, (artifacts / "compositor.log").read_text()
            env["WAYLAND_DISPLAY"] = sockets[0].name
            result = subprocess.run(["qs", "-p", str(base), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            (artifacts / "quickshell.log").write_text(output)
            assert result.returncode == 0 and "UI_TESTS_OK" in output and "FAIL" not in output, output
            assert not any(error in output for error in ("TypeError", "ReferenceError", "Binding loop", "Unable to assign")), output
            assert len(list(artifacts.glob("*.png"))) >= 6, "Missing screenshots"
            print("Isolated Wayland UI: render, menus, real keyboard focus, groups, minimized preview, vertical bar and overflow passed.")
            if "SPACES_UI_ARTIFACTS" in os.environ:
                print(f"Screenshots and logs: {artifacts}")
        finally:
            compositor.terminate()
            try:
                compositor.wait(timeout=5)
            except subprocess.TimeoutExpired:
                compositor.kill()
                compositor.wait()
