#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
EXPECTED="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
with_hyprbars=false
case ${1:-} in
  '') ;;
  --with-hyprbars) with_hyprbars=true ;;
  *) echo 'Usage: install.sh [--with-hyprbars]' >&2; exit 2 ;;
esac
(( $# <= 1 )) || { echo 'Usage: install.sh [--with-hyprbars]' >&2; exit 2; }

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
"$ROOT/scripts/build-backend.sh"
"$ROOT/scripts/doctor.sh" --pre-enable
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/$PLUGIN_ID"
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID" --section left
if $with_hyprbars; then "$ROOT/scripts/setup-hyprbars.sh"; fi
"$ROOT/scripts/doctor.sh"
cat <<MSG
Optional official Hyprbars titlebar integration:
  $ROOT/scripts/setup-hyprbars.sh
MSG
