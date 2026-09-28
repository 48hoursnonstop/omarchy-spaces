#!/usr/bin/env python3
"""Exercise branch selection and rollback against a real local Git remote."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = "tornikegomareli.spaces"


class Update(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / "remote"
        self.source.mkdir()
        self.plugin = self.base / "config/omarchy/plugins" / PLUGIN
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.base / "config"), XDG_DATA_HOME=str(self.base / "data"),
                        XDG_STATE_HOME=str(self.base / "state"), XDG_CACHE_HOME=str(self.base / "cache"),
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.git(self.source, "init", "-b", "main")
        (self.source / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/update.sh", self.source / "scripts/update.sh")
        shutil.copy2(ROOT / "scripts/installation-state.py", self.source / "scripts/installation-state.py")
        config = self.base / "config/omarchy/shell.json"
        config.parent.mkdir(parents=True)
        config.write_text('{"bar":{"layout":{"left":[{"id":"tornikegomareli.spaces"}],"right":[{"id":"omarchy.power"}]}},"plugins":[]}')
        for name in ("doctor.sh", "setup-hyprbars.sh"):
            self.script(self.source / "scripts" / name, "exit 0")
        self.script(self.source / "scripts/build-backend.sh", '''
[[ ${MOCK_BUILD_FAIL:-0} == 0 ]] || exit 1
dest="$XDG_DATA_HOME/tornikegomareli.spaces/bin"
mkdir -p "$dest"
printf '#!/bin/sh\\necho new\\n' > "$dest/spaces-backend"
chmod +x "$dest/spaces-backend"
''')
        (self.source / "version").write_text("old")
        self.git(self.source, "add", ".")
        self.git(self.source, "commit", "-m", "initial")
        self.git(self.source, "branch", "release")
        self.git(self.source, "clone", "-b", "release", str(self.source), str(self.plugin))
        self.old = self.git(self.plugin, "rev-parse", "HEAD").stdout.strip()
        self.git(self.source, "checkout", "release")
        (self.source / "version").write_text("new")
        self.script(self.source / "scripts/setup-hyprbars.sh", '[[ ${1:-} == --check ]] && exit 0\nexit "${MOCK_SETUP_FAIL:-0}"')
        self.git(self.source, "add", ".")
        self.git(self.source, "commit", "-m", "release update")
        self.script(self.source / "scripts/doctor.sh", 'exit "${MOCK_DOCTOR_FAIL:-0}"')
        self.git(self.source, "add", ".")
        self.git(self.source, "commit", "--amend", "--no-edit")
        # Remote HEAD deliberately points at main, as on the user's fork.
        self.git(self.source, "checkout", "main")
        self.binary = self.base / "data" / PLUGIN / "bin/spaces-backend"
        self.script(self.binary, "echo old")
        for command in ("omarchy", "omarchy-shell"):
            self.script(self.base / "bin" / command, "exit 0")
        self.script(self.base / "bin/sleep", "exit 0")
        self.env["PATH"] = str(self.base / "bin") + ":" + self.env["PATH"]

    def git(self, directory, *args):
        return subprocess.run(["git", "-C", str(directory), *args], env=self.env, check=True, capture_output=True, text=True)

    def script(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body + "\n")
        path.chmod(0o755)

    def update(self, ok=True):
        result = subprocess.run([str(self.plugin / "scripts/update.sh"), "--yes"], env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)

    def test_follows_installed_branch_and_refreshes_helper(self):
        self.update()
        self.assertEqual((self.plugin / "version").read_text(), "new")
        config = json.loads((self.base / "config/omarchy/shell.json").read_text())
        self.assertEqual(config["bar"]["layout"]["right"][-1]["id"], PLUGIN + ".desktop")
        self.assertIn("echo new", self.binary.read_text())
        self.assertEqual(self.git(self.plugin, "status", "--porcelain").stdout, "")

    def test_failed_activation_restores_previous_bar_without_corner_entry(self):
        config = self.base / "config/omarchy/shell.json"
        before = json.loads(config.read_text())
        self.env["MOCK_DOCTOR_FAIL"] = "1"
        self.update(ok=False)
        self.assertEqual(json.loads(config.read_text()), before)
        self.assertEqual(self.git(self.plugin, "rev-parse", "HEAD").stdout.strip(), self.old)

    def test_failed_build_keeps_installed_version(self):
        self.env["MOCK_BUILD_FAIL"] = "1"
        self.update(ok=False)
        self.assertEqual(self.git(self.plugin, "rev-parse", "HEAD").stdout.strip(), self.old)
        self.assertIn("echo old", self.binary.read_text())

    def test_failed_titlebar_update_rolls_back_source_and_helper(self):
        self.env["MOCK_SETUP_FAIL"] = "1"
        self.update(ok=False)
        self.assertEqual(self.git(self.plugin, "rev-parse", "HEAD").stdout.strip(), self.old)
        self.assertIn("echo old", self.binary.read_text())

    def test_uncommitted_user_changes_are_preserved(self):
        (self.plugin / "version").write_text("user edit")
        self.update(ok=False)
        self.assertEqual((self.plugin / "version").read_text(), "user edit")


if __name__ == "__main__":
    unittest.main(verbosity=2)
