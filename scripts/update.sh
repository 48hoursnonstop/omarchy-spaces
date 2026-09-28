#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

EXPECTED="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
[[ $(realpath "$ROOT") == "$(realpath -m "$EXPECTED")" ]] || { echo 'Run update from the installed plugin directory.' >&2; exit 2; }
[[ $# == 0 || ( $# == 1 && $1 == --yes ) ]] || { echo 'Usage: update.sh [--yes]' >&2; exit 2; }
[[ -z $(git -C "$ROOT" status --porcelain) ]] || { echo 'Commit or save local source changes before updating.' >&2; exit 2; }
branch=$(git -C "$ROOT" symbolic-ref --short HEAD)
remote=$(git -C "$ROOT" config "branch.$branch.remote")
ref=$(git -C "$ROOT" config "branch.$branch.merge")
[[ -n $remote && $remote != . && $ref == refs/heads/* ]] || { echo 'The installed branch must track a remote branch.' >&2; exit 2; }
git -C "$ROOT" fetch "$remote" "$ref"
old=$(git -C "$ROOT" rev-parse HEAD)
next=$(git -C "$ROOT" rev-parse FETCH_HEAD)
git -C "$ROOT" merge-base --is-ancestor "$old" "$next" || { echo 'Update is not a fast-forward.' >&2; exit 2; }
if [[ $old == "$next" ]]; then exec "$ROOT/scripts/doctor.sh"; fi

mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
staging=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/spaces-update.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
mkdir "$staging/source"
git -C "$ROOT" archive "$next" | tar -x -C "$staging/source"
omarchy plugin validate "$staging/source"
XDG_DATA_HOME="$staging/data" "$staging/source/scripts/build-backend.sh"
"$staging/source/scripts/setup-hyprbars.sh" --check

BIN="${XDG_DATA_HOME:-$HOME/.local/share}/$PLUGIN_ID/bin/spaces-backend"
[[ -x $BIN ]] || { echo 'Missing installed helper. Run install.sh first.' >&2; exit 2; }
cp -p -- "$BIN" "$staging/previous-backend"
python3 "$staging/source/scripts/installation-state.py" checkpoint "$staging/placement.json"
rollback() {
  local code=$?
  trap - ERR
  # The checkout was verified clean before starting the update.
  python3 "$staging/source/scripts/installation-state.py" restore-checkpoint "$staging/placement.json" || true
  git -C "$ROOT" reset --hard "$old"
  install -m 0755 "$staging/previous-backend" "$BIN.rollback"
  mv -f -- "$BIN.rollback" "$BIN"
  "$ROOT/scripts/setup-hyprbars.sh" || true
  omarchy-shell shell rescanPlugins >/dev/null || true
  echo 'Update failed; previous source and helper restored. Restore journal was retained.' >&2
  exit "$code"
}
trap rollback ERR
git -C "$ROOT" merge --ff-only "$next"
install -m 0755 "$staging/data/$PLUGIN_ID/bin/spaces-backend" "$BIN.next"
mv -f -- "$BIN.next" "$BIN"
"$ROOT/scripts/setup-hyprbars.sh"
python3 "$ROOT/scripts/installation-state.py" capture
python3 "$ROOT/scripts/installation-state.py" place
omarchy-shell shell rescanPlugins
for _attempt in {1..60}; do
  if "$ROOT/scripts/doctor.sh" >"$staging/check.log" 2>&1; then
    trap - ERR
    cat "$staging/check.log"
    echo "Updated Spaces and Hyprbars from $remote/${ref#refs/heads/}."
    exit 0
  fi
  sleep 0.25
done
cat "$staging/check.log" >&2
false
