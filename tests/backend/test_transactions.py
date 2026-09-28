#!/usr/bin/env python3
"""Run against the compiled CLI, never a live Hyprland session."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

BINARY = Path(os.environ['SPACES_TEST_BINARY']).resolve()
PLUGIN = 'tornikegomareli.spaces'
HIDDEN = 'special:omarchy-spaces-minimized'


def window(address='0xabc', **fields):
    return dict(address=address, workspace={'id': 1, 'name': '1'}, floating=True,
                fullscreen=2, fullscreenClient=2, pinned=True, pseudo=True,
                at=[40, 80], size=[800, 600], pid=123, **fields)


class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'bin').mkdir()
        (self.root / 'runtime').mkdir()
        mock = self.root / 'bin/hyprctl'
        shutil.copy(Path(__file__).with_name('mock_hyprctl.py'), mock)
        mock.chmod(0o755)
        self.compositor = self.root / 'compositor.json'
        self.compositor.write_text(json.dumps({'clients': [window()], 'active': '0xabc'}))
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + ':' + os.environ['PATH'],
                        MOCK_COMPOSITOR=str(self.compositor), XDG_STATE_HOME=str(self.root / 'state'),
                        XDG_RUNTIME_DIR=str(self.root / 'runtime'))
        self.state_path = self.root / 'state' / PLUGIN / 'restore-v1.json'

    def cli(self, *args, ok=True, protocol='6'):
        result = subprocess.run([str(BINARY), '--protocol', protocol, *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        obj = json.loads(result.stdout)
        self.assertEqual(result.returncode == 0, ok, (args, result.stdout, result.stderr))
        self.assertEqual(obj['ok'], ok)
        return obj

    def model(self):
        return json.loads(self.compositor.read_text())

    def change(self, **fields):
        model = self.model()
        model.update(fields)
        self.compositor.write_text(json.dumps(model))

    def test_preserves_window_state(self):
        original = self.model()['clients'][0]
        self.cli('minimize', '0xabc')
        self.assertEqual(self.model()['clients'][0]['workspace']['name'], HIDDEN)
        self.cli('restore', '0xabc', '--focus')
        self.assertEqual(self.model()['clients'][0], original)
        self.assertEqual(self.cli('snapshot')['minimized'], [])

    def test_minimize_records_original_monitor(self):
        self.change(clients=[window(monitor=3)])
        self.cli('minimize', '0xabc')
        record = self.cli('snapshot')['minimized'][0]
        self.assertEqual(record['monitor_id'], 3)
        self.assertEqual(record['workspace_id'], 1)

    def test_show_desktop_targets_explicit_workspace_without_stealing_focus(self):
        other = window('0xdef')
        other['workspace'] = {'id': 4, 'name': '4'}
        self.change(clients=[window(), other])
        self.cli('show-desktop-toggle', '4')
        self.assertEqual(self.model()['clients'][0]['workspace']['id'], 1)
        self.assertEqual(self.model()['clients'][1]['workspace']['name'], HIDDEN)
        self.assertIsNone(self.cli('snapshot')['minimized'][0]['original_active'])
        self.cli('show-desktop-toggle', '4')
        self.assertEqual(self.model()['active'], '0xabc')
        self.assertEqual(self.model()['clients'][1]['workspace']['id'], 4)

    def test_restore_workspace_leaves_other_workspaces_minimized(self):
        other = window('0xdef')
        other['workspace'] = {'id': 4, 'name': '4'}
        self.change(clients=[window(), other])
        self.cli('minimize', '0xabc')
        self.cli('minimize', '0xdef')
        self.cli('restore-workspace', '4')
        self.assertEqual([r['address'] for r in self.cli('snapshot')['minimized']], ['0xabc'])
        self.assertEqual(self.model()['clients'][1]['workspace']['id'], 4)

    def test_other_taskbar_state_is_isolated(self):
        foreign = self.root / 'state/workspace-taskbar/restore-v1.json'
        foreign.parent.mkdir(parents=True)
        foreign.write_text('not our state')
        self.cli('minimize', '0xabc')
        self.cli('restore-all')
        self.assertEqual(foreign.read_text(), 'not our state')

    def test_restore_failure_retains_pending_state(self):
        self.cli('minimize', '0xabc')
        self.change(fail='.float(')
        self.cli('restore', '0xabc', ok=False)
        self.assertTrue(self.cli('snapshot')['minimized'][0]['pending'])
        self.cli('doctor-json', ok=False)
        self.change(fail='')
        self.cli('recover')
        self.assertEqual(self.model()['clients'][0]['fullscreen'], 2)
        self.assertEqual(self.cli('doctor-json')['records'], 0)

    def test_minimize_failure_retains_original_state(self):
        self.change(fail='workspace = ')
        self.cli('minimize', '0xabc', ok=False)
        self.assertTrue(self.cli('snapshot')['minimized'][0]['pending'])
        self.change(fail='')
        self.cli('recover')
        self.assertEqual(self.model()['clients'][0]['fullscreen'], 2)
        self.assertTrue(self.model()['clients'][0]['pinned'])

    def test_group_restores_every_member(self):
        a, b = window(), window('0xdef')
        a['grouped'] = b['grouped'] = ['0xabc', '0xdef']
        self.change(clients=[a, b])
        self.cli('minimize', '0xabc')
        self.assertEqual(len(self.cli('snapshot')['minimized']), 2)
        self.cli('restore', '0xdef')
        self.assertTrue(all(c['workspace']['name'] == '1' for c in self.model()['clients']))
        self.assertEqual(self.cli('snapshot')['minimized'], [])

    def test_show_desktop_restores_only_batch_and_focus(self):
        self.change(clients=[window(), window('0xdef'), window('0x123')], active='0xdef')
        self.cli('minimize', '0x123')
        self.cli('show-desktop-toggle', '1')
        self.assertEqual(len(self.cli('snapshot')['minimized']), 3)
        self.cli('show-desktop-toggle', '1')
        self.assertEqual([r['address'] for r in self.cli('snapshot')['minimized']], ['0x123'])
        self.assertEqual(self.model()['active'], '0xdef')
        self.cli('restore-last')
        self.assertEqual(self.cli('snapshot')['minimized'], [])

    def test_external_move_reconciles_completed_minimize(self):
        self.cli('minimize', '0xabc')
        client = self.model()['clients'][0]
        client['workspace'] = {'id': 2, 'name': '2'}
        self.change(clients=[client])
        self.assertEqual(self.cli('snapshot')['minimized'], [])
        self.cli('recover')
        self.assertEqual(self.model()['clients'][0]['workspace']['id'], 2)

    def test_menu_move_restores_minimized_state_on_destination(self):
        self.cli('minimize', '0xabc')
        self.cli('window-action', 'move-workspace', '0xabc', '3')
        client = self.model()['clients'][0]
        self.assertEqual(client['workspace']['id'], 3)
        self.assertEqual(client['fullscreen'], 2)
        self.assertTrue(client['pinned'])
        self.assertEqual(self.cli('snapshot')['minimized'], [])

    def test_orphan_recovery_and_doctor_exit(self):
        client = window()
        client['workspace'] = {'id': -99, 'name': HIDDEN}
        self.change(clients=[client])
        self.cli('doctor-json', ok=False)
        self.cli('recover')
        self.assertEqual(self.model()['clients'][0]['workspace']['name'], '1')
        self.cli('doctor-json')

    def test_incompatible_protocol_has_no_side_effects(self):
        before = self.compositor.read_text()
        self.cli('minimize', '0xabc', protocol='999', ok=False)
        self.assertEqual(self.compositor.read_text(), before)
        self.assertFalse(self.state_path.exists())

    def test_unreviewed_hyprland_refuses_mutation(self):
        self.change(version='Hyprland 0.99.0')
        self.cli('minimize', '0xabc', ok=False)
        self.assertFalse(any(c[0] == 'dispatch' for c in self.model()['calls']))

    def test_corrupt_state_is_preserved(self):
        self.state_path.parent.mkdir(parents=True)
        self.state_path.write_text('{broken')
        self.cli('recover', ok=False)
        self.assertEqual(self.state_path.read_text(), '{broken')
        self.assertFalse(any(c[0] == 'dispatch' for c in self.model()['calls']))

    def test_lock_contention_then_process_exit(self):
        lock = self.root / 'runtime' / PLUGIN / 'transaction.lock'
        lock.parent.mkdir()
        with lock.open('w') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.cli('minimize', '0xabc', ok=False)
        self.cli('minimize', '0xabc')
        self.cli('restore-all')

    def test_address_reuse_does_not_restore_old_client(self):
        self.cli('minimize', '0xabc')
        client = self.model()['clients'][0]
        client['pid'] = 999
        self.change(clients=[client])
        self.assertEqual(self.cli('snapshot')['minimized'], [])
        self.cli('doctor-json', ok=False)

    def test_state_survives_fresh_process_and_closed_clients(self):
        self.cli('minimize', '0xabc')
        self.assertEqual(len(self.cli('snapshot')['minimized']), 1)
        self.change(clients=[])
        self.assertEqual(self.cli('snapshot')['minimized'], [])
        self.cli('recover')


if __name__ == '__main__':
    unittest.main(verbosity=2)
