#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

printf 'Current plugin: %s\n' "$(jq -r .version "$ROOT/manifest.json")"
BIN="${XDG_DATA_HOME:-$HOME/.local/share}/$PLUGIN_ID/bin/spaces-backend"
if [[ -x $BIN ]]; then "$BIN" version-json; else echo 'Current backend: missing'; fi
omarchy plugin update "$PLUGIN_ID" "$@"
omarchy plugin validate "$ROOT"
"$ROOT/scripts/build-backend.sh"
omarchy-shell shell rescanPlugins
"$ROOT/scripts/doctor.sh"
