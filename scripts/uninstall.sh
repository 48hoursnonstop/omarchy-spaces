#!/usr/bin/env bash
set -euo pipefail
PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
BIN="$DATA_HOME/$PLUGIN_ID/bin/spaces-backend"
[[ $# == 0 || ( $# == 1 && $1 == --yes ) ]] || { echo 'usage: uninstall.sh [--yes]' >&2; exit 2; }
[[ $(realpath "$ROOT") == "$(realpath -m "$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID")" ]] || {
  echo 'Run uninstall from the installed plugin directory.' >&2; exit 2;
}
for tool in jq hyprctl omarchy omarchy-shell; do
  command -v "$tool" >/dev/null || { echo "Missing required command: $tool" >&2; exit 2; }
done
# Stop new UI requests before recovery; any failure keeps restore state intact.
omarchy plugin disable "$PLUGIN_ID"
omarchy-shell shell rescanPlugins >/dev/null
if [[ -x $BIN ]]; then
  "$BIN" --protocol 6 recover
  doctor_json=$("$BIN" --protocol 6 doctor-json)
  jq -e '.ok == true and .records == 0' <<<"$doctor_json" >/dev/null
fi
clients=$(hyprctl -j clients)
jq -e 'type == "array" and all(.[]; .workspace.name != "special:omarchy-spaces-minimized" and .workspace.name != "omarchy-spaces-minimized")' <<<"$clients" >/dev/null || {
  echo 'Hidden windows remain. Rebuild the backend and run recover; all restore state has been retained.' >&2; exit 3;
}
if [[ ! -x $BIN && -f "$STATE_HOME/$PLUGIN_ID/restore-v1.json" ]]; then
  jq -e '.records | length == 0' "$STATE_HOME/$PLUGIN_ID/restore-v1.json" >/dev/null || {
    echo 'Backend missing with unresolved restore records. Rebuild before uninstalling.' >&2; exit 3;
  }
fi
"$ROOT/scripts/setup-hyprbars.sh" --remove
errors=$(hyprctl configerrors)
[[ -z $errors ]] || { printf 'Hyprland config errors: %s\n' "$errors" >&2; exit 4; }
omarchy-shell shell ping >/dev/null
# No mutations remain after this point; preserve the lock inode until all old
# processes have exited. It is ephemeral and the session cleans it up.
rm -rf -- "${DATA_HOME:?}/${PLUGIN_ID:?}" "${STATE_HOME:?}/${PLUGIN_ID:?}" "${CACHE_HOME:?}/${PLUGIN_ID:?}"
if [[ -d "$ROOT/.git" ]]; then
  omarchy plugin remove "$PLUGIN_ID" "$@"
else
  backup="$DATA_HOME/omarchy-plugin-backups/$PLUGIN_ID-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$(dirname "$backup")"
  mv -- "$ROOT" "$backup"
  printf 'Source backed up to %s\n' "$backup"
  omarchy-shell shell rescanPlugins >/dev/null
fi
printf 'Removed %s. Application pins/overrides are preserved in %s/%s.\n' "$PLUGIN_ID" "$CONFIG_HOME" "$PLUGIN_ID"
