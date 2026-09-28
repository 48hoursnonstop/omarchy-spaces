#!/usr/bin/env python3
"""Exercise the real QML service and Process queue without a desktop session."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = "tornikegomareli.spaces"

with tempfile.TemporaryDirectory(prefix="spaces-qml-") as directory:
    base = Path(directory)
    (base / "plugin").symlink_to(ROOT, target_is_directory=True)
    shutil.copy(Path(__file__).with_name("service.qml"), base / "shell.qml")
    for part in ("runtime", "config", "data", "state", "cache"):
        (base / part).mkdir(mode=0o700)
    (base / "config" / PLUGIN).mkdir()
    binary = base / "data" / PLUGIN / "bin/spaces-backend"
    binary.parent.mkdir(parents=True)
    records = [dict(address=address, workspace_id=3, workspace_name="3", monitor_id=2,
                    class_name="Foot", initial_class="Foot", title="Test terminal", pid=123,
                    group_key="0xaaa|0xbbb", floating=False, pinned=False, pseudo=False,
                    fullscreen=0, fullscreen_client=0, at=[0, 0], size=[800, 600])
               for address in ("0xaaa", "0xbbb")]
    (base / "records.json").write_text(json.dumps(records))
    binary.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
base = Path(os.environ['SPACES_QML_FIXTURE'])
with (base / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\\n')
if args == ['version-json']:
    print(json.dumps(dict(ok=True, backendVersion='fixture', protocolVersion=6)))
elif args[:2] != ['--protocol', '6']:
    raise SystemExit('missing protocol')
elif args[2] == 'window-action':
    time.sleep(0.1)
    print(json.dumps(dict(ok=False, error='fixture action failure')))
    sys.exit(1)
else:
    time.sleep(0.1)
    print(json.dumps(dict(ok=True, protocolVersion=6, minimized=json.loads((base / 'records.json').read_text()))))
''')
    binary.chmod(0o755)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", SPACES_QML_FIXTURE=str(base))
    for variable in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
        env.pop(variable, None)
    for part in ("RUNTIME", "CONFIG", "DATA", "STATE", "CACHE"):
        env[f"XDG_{part}_{'DIR' if part == 'RUNTIME' else 'HOME'}"] = str(base / part.lower())
    result = subprocess.run(["qs", "-p", str(base), "--no-color"], env=env,
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SERVICE_TESTS_OK" in output and "FAIL" not in output, output
    assert not any(error in output for error in ("TypeError", "ReferenceError", "Binding loop")), output
    pins = json.loads((base / "config" / PLUGIN / "pins.json").read_text())
    assert pins == {"desktopIds": ["terminal"]}, pins
    calls = [json.loads(line) for line in (base / "calls.jsonl").read_text().splitlines()]
    assert ["--protocol", "6", "show-desktop-toggle", "3"] in calls, calls
    assert sum(call[2:3] == ["show-desktop-toggle"] for call in calls) == 1, calls
    assert sum(call[2:3] == ["window-action"] for call in calls) == 1, calls
    print("Real QML service: identity, persistence, batch/group locking, Process completion and error retention passed.")
