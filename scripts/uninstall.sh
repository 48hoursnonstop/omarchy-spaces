#!/usr/bin/env bash
set -euo pipefail
PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
BIN="$DATA_HOME/$PLUGIN_ID/bin/spaces-backend"
keep_settings=false
yes=false
for arg in "$@"; do
  case $arg in
    --yes) yes=true ;;
    --keep-settings) keep_settings=true ;;
    *) echo 'usage: uninstall.sh [--yes] [--keep-settings]' >&2; exit 2 ;;
  esac
done
if ! $yes; then
  [[ -t 0 ]] || { echo 'Pass --yes to remove Spaces, Hyprbars integration and Spaces preferences.' >&2; exit 2; }
  read -r -p 'Remove Spaces, its Hyprbars integration and preferences? [y/N] ' answer
  [[ $answer == y || $answer == Y ]] || exit 0
fi
[[ $(realpath "$ROOT") == "$(realpath -m "$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID")" ]] || {
  echo 'Run uninstall from the installed plugin directory.' >&2; exit 2;
}
for tool in jq hyprctl omarchy omarchy-shell python3; do
  command -v "$tool" >/dev/null || { echo "Missing required command: $tool" >&2; exit 2; }
done
# Stop new UI requests before recovery; any failure keeps restore state intact.
omarchy plugin disable "$PLUGIN_ID"
omarchy-shell shell rescanPlugins >/dev/null
# Remove the other source of minimize requests before recovering windows.
# On failure, source/helper/journal remain available to retry recovery.
"$ROOT/scripts/setup-hyprbars.sh" --remove
if [[ -x $BIN ]]; then
  for _attempt in {1..20}; do
    if result=$("$BIN" --protocol 6 recover); then break; fi
    jq -e '.busy == true' <<<"$result" >/dev/null || { printf '%s\n' "$result" >&2; exit 3; }
    sleep 0.1
  done
  jq -e '.ok == true' <<<"$result" >/dev/null || { printf '%s\n' "$result" >&2; exit 3; }
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
errors=$(hyprctl configerrors)
[[ -z $errors ]] || { printf 'Hyprland config errors: %s\n' "$errors" >&2; exit 4; }
omarchy-shell shell ping >/dev/null
python3 "$ROOT/scripts/installation-state.py" remove
# No mutations remain after this point; preserve the lock inode until all old
# processes have exited. It is ephemeral and the session cleans it up.
rm -rf -- "${DATA_HOME:?}/${PLUGIN_ID:?}" "${STATE_HOME:?}/${PLUGIN_ID:?}" "${CACHE_HOME:?}/${PLUGIN_ID:?}"
if ! $keep_settings; then rm -rf -- "${CONFIG_HOME:?}/${PLUGIN_ID:?}"; fi
installed="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
if [[ -L $installed ]]; then
  rm -- "$installed"
else
  rm -rf -- "${installed:?}"
fi
omarchy-shell shell rescanPlugins >/dev/null
printf 'Removed %s, managed Hyprbars integration and runtime data.\n' "$PLUGIN_ID"
if $keep_settings; then printf 'Preferences retained in %s/%s.\n' "$CONFIG_HOME" "$PLUGIN_ID"; fi
