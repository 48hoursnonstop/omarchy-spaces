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
        for name in ('install.sh', 'uninstall.sh', 'doctor.sh', 'installation-state.py'):
            shutil.copy(ROOT / 'scripts' / name, self.plugin / 'scripts' / name)
        self.executable(self.plugin / 'scripts/setup-hyprbars.sh', 'exit 0')
        self.executable(self.plugin / 'scripts/build-backend.sh', 'exit 0')
        shutil.copy(ROOT / 'manifest.json', self.plugin / 'manifest.json')
        self.state = self.base / 'state' / PLUGIN
        self.state.mkdir(parents=True)
        (self.state / 'restore-v1.json').write_text('{"records":[]}')
        self.preferences = self.base / 'config' / PLUGIN
        self.preferences.mkdir()
        (self.preferences / 'pins.json').write_text('{"desktopIds":["foot"]}')
        self.shell_config = self.base / 'config/omarchy/shell.json'
        self.original_shell = {'bar': {'layout': {'left': [{'id':'omarchy.menu'}, {'id':'omarchy.workspaces','persistentWorkspaces':4}], 'right':[{'id':'omarchy.clock'}]}}, 'plugins':[]}
        self.shell_config.write_text(json.dumps(self.original_shell))
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.executable(self.bin / 'omarchy', '''
if [[ $1 == plugin && $2 == disable && ${MOCK_DISABLE_FAIL:-0} == 1 ]]; then exit 1; fi
if [[ $1 == plugin && $2 == list ]]; then echo '[{"id":"tornikegomareli.spaces","enabled":true}]'; fi
''')
        self.executable(self.bin / 'omarchy-shell', '[[ ${2:-} == rescanPlugins && ${MOCK_RESCAN_FAIL:-0} == 1 ]] && exit 1\necho ok')
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
                        CLAUDE_CONFIG_DIR=str(self.base / 'claude'),
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
        result = subprocess.run([str(self.plugin / 'scripts' / name), *(['--yes'] if name == 'uninstall.sh' else []), *args], env=self.env,
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

    def test_clean_uninstall_removes_source_preferences_and_state(self):
        self.run_script('uninstall.sh')
        self.assertFalse(self.plugin.exists())
        self.assertFalse(self.state.exists())
        self.assertFalse(self.preferences.exists())
        self.assertFalse((self.base / 'data/omarchy-plugin-backups').exists())

    def installation_state(self, action):
        subprocess.run(['python3', str(self.plugin / 'scripts/installation-state.py'), action], env=self.env, check=True, capture_output=True)

    def test_keep_settings_is_explicit(self):
        self.run_script('uninstall.sh', '--keep-settings')
        self.assertTrue((self.preferences / 'pins.json').exists())

    def test_unlinks_installation_without_deleting_development_checkout(self):
        development = self.base / 'development'
        self.plugin.rename(development)
        self.plugin.symlink_to(development, target_is_directory=True)
        self.run_script('uninstall.sh')
        self.assertFalse(self.plugin.exists())
        self.assertTrue((development / 'manifest.json').exists())

    def test_shell_config_symlink_survives_install_and_remove(self):
        target = self.base / 'dotfiles/shell.json'
        target.parent.mkdir()
        self.shell_config.rename(target)
        self.shell_config.symlink_to(target)
        self.installation_state('capture')
        self.installation_state('place')
        self.run_script('uninstall.sh')
        self.assertTrue(self.shell_config.is_symlink())
        self.assertEqual(json.loads(target.read_text()), self.original_shell)

    def test_installer_includes_hyprbars_and_replaces_workspaces(self):
        self.executable(self.plugin / 'scripts/doctor.sh', 'exit 0')
        log = self.base / 'hyprbars-calls'
        self.executable(self.plugin / 'scripts/setup-hyprbars.sh', 'echo "${1:-install}" >> ' + str(log))
        self.run_script('install.sh')
        self.assertEqual(log.read_text().splitlines(), ['--check', 'install'])
        installed = json.loads(self.shell_config.read_text())
        self.assertEqual(installed['bar']['layout']['left'][1]['id'], PLUGIN)
        self.assertEqual(installed['plugins'], [])
        self.assertTrue(json.loads((self.state / 'installation-v1.json').read_text())['complete'])
        self.run_script('install.sh')
        self.run_script('uninstall.sh')
        self.assertEqual(json.loads(self.shell_config.read_text()), self.original_shell)

    def test_install_registry_failure_restores_previous_bar(self):
        self.executable(self.plugin / 'scripts/doctor.sh', 'exit 0')
        self.env['MOCK_RESCAN_FAIL'] = '1'
        self.run_script('install.sh', ok=False)
        self.assertEqual(json.loads(self.shell_config.read_text()), self.original_shell)
        self.assertFalse(json.loads((self.state / 'installation-v1.json').read_text())['complete'])
        self.assertTrue(self.backend.exists())

    def test_restores_workspace_placement_without_reverting_unrelated_edits(self):
        self.installation_state('capture')
        self.installation_state('place')
        changed = json.loads(self.shell_config.read_text())
        changed['bar']['layout']['right'].append({'id':'omarchy.audio'})
        self.shell_config.write_text(json.dumps(changed))
        self.run_script('uninstall.sh')
        final = json.loads(self.shell_config.read_text())
        self.assertEqual(final['bar']['layout']['left'], self.original_shell['bar']['layout']['left'])
        self.assertEqual(final['bar']['layout']['right'][-1]['id'], 'omarchy.audio')
        self.assertEqual(final['plugins'], [])

    def test_failed_hyprbars_removal_keeps_recovery_data(self):
        self.executable(self.plugin / 'scripts/setup-hyprbars.sh', 'exit 3')
        self.run_script('uninstall.sh', ok=False)
        self.assertTrue(self.backend.exists())
        self.assertTrue(self.state.exists())
        self.assertTrue(self.preferences.exists())

    def test_removes_only_spaces_agent_commands(self):
        claude = self.base / 'claude/settings.json'
        claude.parent.mkdir()
        ours = {'type':'command','command':'~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/claude-hook working'}
        other = {'type':'command','command':'other-agent-hook'}
        claude.write_text(json.dumps({'model':'kept','hooks':{'Stop':[{'hooks':[ours,other]}]}}))
        self.run_script('uninstall.sh')
        self.assertEqual(json.loads(claude.read_text()), {'model':'kept','hooks':{'Stop':[{'hooks':[other]}]}})

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
