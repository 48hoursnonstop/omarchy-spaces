#!/usr/bin/env python3
"""Installer lifecycle regression tests in isolated XDG roots and mocked IPC."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = 'tornikegomareli.spaces'


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.plugin = self.base / 'config/omarchy/plugins' / PLUGIN
        (self.plugin / 'scripts').mkdir(parents=True)
        for name in ('uninstall.sh', 'doctor.sh'):
            shutil.copy(ROOT / 'scripts' / name, self.plugin / 'scripts' / name)
        self.executable(self.plugin / 'scripts/setup-hyprbars.sh', 'exit 0')
        shutil.copy(ROOT / 'manifest.json', self.plugin / 'manifest.json')
        self.state = self.base / 'state' / PLUGIN
        self.state.mkdir(parents=True)
        (self.state / 'restore-v1.json').write_text('{"records":[]}')
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.executable(self.bin / 'omarchy', '''
if [[ $1 == plugin && $2 == disable && ${MOCK_DISABLE_FAIL:-0} == 1 ]]; then exit 1; fi
if [[ $1 == plugin && $2 == list ]]; then echo '[{"id":"tornikegomareli.spaces","enabled":true}]'; fi
''')
        self.executable(self.bin / 'omarchy-shell', 'echo ok')
        self.executable(self.bin / 'hyprctl', '''
case "$*" in
  '-j clients') echo "${MOCK_CLIENTS:-[]}" ;;
  version) echo 'Hyprland 0.56.2' ;;
  configerrors) exit "${MOCK_CONFIG_FAIL:-0}" ;;
  'plugin list') echo '' ;;
  *) exit 2 ;;
esac
''')
        self.executable(self.bin / 'pacman', "echo 'omarchy 4.0.4-1'")
        self.executable(self.bin / 'qs', "echo 'quickshell 0.3.1'")
        self.executable(self.bin / 'hyprpm', 'echo none')
        services = self.base / 'omarchy/shell/services'
        services.mkdir(parents=True)
        (services / 'PluginShellApi.qml').write_text('function serviceFor(id) {}\n')
        (services / 'PluginAppLibraryApi.qml').write_text(
            'function sortedEntries(query) {}\nfunction iconSource(icon) {}\n')
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        OMARCHY_PATH=str(self.base / 'omarchy'),
                        XDG_CONFIG_HOME=str(self.base / 'config'), XDG_DATA_HOME=str(self.base / 'data'),
                        XDG_STATE_HOME=str(self.base / 'state'), XDG_CACHE_HOME=str(self.base / 'cache'))
        self.backend = self.base / 'data' / PLUGIN / 'bin/spaces-backend'
        self.backend.parent.mkdir(parents=True)
        self.executable(self.backend, '''
if [[ $* == *version-json* ]]; then echo '{"ok":true,"protocolVersion":6,"stateSchemaVersion":1}'
elif [[ $* == *doctor-json* ]]; then
  if [[ ${MOCK_STATE_BAD:-0} == 1 ]]; then echo '{"ok":false,"strandedError":"orphan"}'; exit 1; fi
  echo '{"ok":true,"records":0}'
else echo '{"ok":true}'; fi
''')

    def executable(self, path, body):
        path.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self, name, *args, ok=True):
        result = subprocess.run([str(self.plugin / 'scripts' / name), *args], env=self.env,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def test_missing_backend_preserves_hidden_window_state(self):
        self.backend.unlink()
        self.env['MOCK_CLIENTS'] = json.dumps([{'workspace': {'name': 'special:omarchy-spaces-minimized'}}])
        self.run_script('uninstall.sh', ok=False)
        self.assertTrue((self.state / 'restore-v1.json').exists())
        self.assertTrue(self.plugin.exists())

    def test_missing_backend_preserves_pending_visible_records(self):
        self.backend.unlink()
        (self.state / 'restore-v1.json').write_text('{"records":[{"pending":true}]}')
        self.run_script('uninstall.sh', ok=False)
        self.assertTrue(self.state.exists())

    def test_disable_failure_aborts_before_cleanup(self):
        self.env['MOCK_DISABLE_FAIL'] = '1'
        self.run_script('uninstall.sh', ok=False)
        self.assertTrue(self.backend.exists())
        self.assertTrue(self.state.exists())

    def test_failed_recovery_aborts_before_cleanup(self):
        self.env['MOCK_STATE_BAD'] = '1'
        self.run_script('uninstall.sh', ok=False)
        self.assertTrue(self.state.exists())

    def test_manual_source_is_backed_up(self):
        self.run_script('uninstall.sh')
        self.assertFalse(self.plugin.exists())
        self.assertFalse(self.state.exists())
        self.assertEqual(len(list((self.base / 'data/omarchy-plugin-backups').iterdir())), 1)

    def test_doctor_propagates_bad_state(self):
        self.env['MOCK_STATE_BAD'] = '1'
        self.run_script('doctor.sh', '--pre-enable', ok=False)

    def test_doctor_distinguishes_failed_config_query(self):
        self.env['MOCK_CONFIG_FAIL'] = '1'
        result = self.run_script('doctor.sh', '--pre-enable', ok=False)
        self.assertIn('query failed', result.stdout)

    def test_pre_enable_skips_only_service_and_placement(self):
        self.run_script('doctor.sh', '--pre-enable')
        self.run_script('doctor.sh', ok=False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
