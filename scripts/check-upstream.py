#!/usr/bin/env python3
"""Flag public contract changes for human review; never update compatibility automatically."""
import hashlib
import json
from pathlib import Path
import sys
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
compat = json.loads((ROOT / 'compat/upstream.json').read_text())['omarchy']


def fetch(url):
    with urlopen(Request(url, headers={'User-Agent': 'tornikegomareli.spaces-compat'}), timeout=30) as response:
        return response.read()


tag = json.loads(fetch('https://api.github.com/repos/omacom/omarchy/releases/latest'))['tag_name']
changed = []
for path, expected in compat['reviewedFiles'].items():
    body = fetch(f'https://raw.githubusercontent.com/omacom/omarchy/{tag}/{path}')
    actual = hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body).hexdigest()
    print(f'{path}: {actual}')
    if actual != expected:
        changed.append(path)
if tag != compat['tag'] or changed:
    print(f'Compatibility review required: baseline {compat["tag"]}, upstream {tag}; changed files: {changed}', file=sys.stderr)
    sys.exit(1)
print('Reviewed public contract unchanged.')
