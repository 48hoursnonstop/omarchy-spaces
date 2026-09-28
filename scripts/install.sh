#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
EXPECTED="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
[[ $# == 0 || ( $# == 1 && $1 == --with-hyprbars ) ]] || { echo 'Usage: install.sh' >&2; exit 2; }

command -v omarchy >/dev/null || { echo "Omarchy CLI not found." >&2; exit 2; }

root_real=$(realpath -m "$ROOT")
expected_real=$(realpath -m "$EXPECTED")
if [[ $root_real != "$expected_real" ]]; then
  cat >&2 <<MSG
This checkout must live at:
  $EXPECTED
Current checkout:
  $ROOT

Move/clone the repository to Omarchy's documented third-party plugin path first.
MSG
  exit 2
fi

omarchy plugin validate "$ROOT"
"$ROOT/scripts/setup-hyprbars.sh" --check
"$ROOT/scripts/build-backend.sh"
"$ROOT/scripts/doctor.sh" --pre-enable
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/$PLUGIN_ID"
state="${XDG_STATE_HOME:-$HOME/.local/state}/$PLUGIN_ID/installation-v1.json"
new_install=true
if [[ -f $state ]] && jq -e '.complete == true' "$state" >/dev/null; then new_install=false; fi
python3 "$ROOT/scripts/installation-state.py" capture
rollback() {
  local code=$?
  trap - ERR
  if $new_install; then
    "$ROOT/scripts/setup-hyprbars.sh" --remove || true
    python3 "$ROOT/scripts/installation-state.py" rollback || true
    omarchy-shell shell rescanPlugins >/dev/null || true
  fi
  echo 'Installation did not complete. Source and recovery data remain available for retry or uninstall.' >&2
  exit "$code"
}
set -E
trap rollback ERR
"$ROOT/scripts/setup-hyprbars.sh"
omarchy-shell shell rescanPlugins
python3 "$ROOT/scripts/installation-state.py" place
# Layout presence activates a native widget and its service. Updating layout
# and activation together avoids racing a CLI write against the file watcher.
omarchy-shell shell rescanPlugins
# Service startup and the first helper probe are asynchronous.
for _attempt in {1..60}; do
  if "$ROOT/scripts/doctor.sh" >"${state%/*}/install-check.log" 2>&1; then
    python3 "$ROOT/scripts/installation-state.py" complete
    trap - ERR
    cat "${state%/*}/install-check.log"
    echo 'Spaces and Hyprbars installed. Uninstall with scripts/uninstall.sh --yes.'
    exit 0
  fi
  sleep 0.25
done
cat "${state%/*}/install-check.log" >&2
false
