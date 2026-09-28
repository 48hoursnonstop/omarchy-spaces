#!/usr/bin/env python3
"""Compositor test double: persistent clients, failure injection, group moves."""
import json
import os
from pathlib import Path
import re
import sys

path = Path(os.environ['MOCK_COMPOSITOR'])
state = json.loads(path.read_text())
args = sys.argv[1:]
state.setdefault('calls', []).append(args)
path.write_text(json.dumps(state))
if args == ['version']:
    print(state.get('version', 'Hyprland 0.56.2 test compositor'))
elif args == ['-j', 'clients']:
    print(json.dumps(state['clients']))
elif args == ['-j', 'activewindow']:
    print(json.dumps(next((c for c in state['clients'] if c['address'] == state.get('active')), {})))
elif args == ['-j', 'activeworkspace']:
    print(json.dumps({'id': 1, 'name': '1'}))
elif args[0] == 'dispatch':
    expr = args[1]
    if state.get('fail') and state['fail'] in expr:
        print('error: injected failure')
        sys.exit(1)
    address = re.search(r'address:(0x[0-9a-f]+)', expr)
    client = next((c for c in state['clients'] if address and c['address'] == address[1]), None)
    if client is None:
        raise SystemExit('unexpected target: ' + expr)
    if expr.startswith('hl.dsp.focus('):
        state['active'] = client['address']
    elif expr.startswith('hl.dsp.window.close('):
        state['clients'].remove(client)
    elif 'workspace = ' in expr:
        ws = re.search(r'workspace = "([^"]+)"', expr)[1]
        for member in state['clients']:
            if member['address'] in client.get('grouped', []) + [client['address']]:
                member['workspace'] = {'id': int(ws) if ws.isdigit() else -99, 'name': ws}
    elif '.fullscreen_state(' in expr:
        client['fullscreen'] = int(re.search(r'internal = (\d+)', expr)[1])
        client['fullscreenClient'] = int(re.search(r'client = (\d+)', expr)[1])
    elif '.float(' in expr:
        client['floating'] = '"set"' in expr
    elif '.pin(' in expr:
        client['pinned'] = '"set"' in expr
    elif '.pseudo(' in expr:
        client['pseudo'] = '"set"' in expr
    elif '.move(' in expr or '.resize(' in expr:
        key = 'at' if '.move(' in expr else 'size'
        client[key] = [int(re.search(r'x = (-?\d+)', expr)[1]), int(re.search(r'y = (-?\d+)', expr)[1])]
    else:
        raise SystemExit('unsupported mock dispatcher: ' + expr)
    path.write_text(json.dumps(state))
    print('ok')
else:
    raise SystemExit('unexpected mock call: ' + repr(args))
