#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/data/tornikegomareli.spaces/bin"
LOG="$TMP/calls.log"

cat > "$TMP/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == activewindow && ${2:-} == -j ]]; then
  printf '%s\n' '{"address":"0xabc123"}'
elif [[ ${1:-} == dispatch ]]; then
  printf 'hyprctl:%s\n' "$2" >> "$CALL_LOG"
else
  exit 2
fi
MOCK

cat > "$TMP/bin/jq" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
# The helper only needs the activewindow address in this smoke test.
cat >/dev/null
printf '%s\n' '0xabc123'
MOCK

cat > "$TMP/data/tornikegomareli.spaces/bin/spaces-backend" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'backend:%s\n' "$*" >> "$CALL_LOG"
MOCK

chmod +x "$TMP/bin/hyprctl" "$TMP/bin/jq" \
  "$TMP/data/tornikegomareli.spaces/bin/spaces-backend"

export PATH="$TMP/bin:$PATH"
export XDG_DATA_HOME="$TMP/data"
export CALL_LOG="$LOG"

"$ROOT/scripts/hyprbars-action.sh" minimize
"$ROOT/scripts/hyprbars-action.sh" maximize
"$ROOT/scripts/hyprbars-action.sh" close

grep -Fqx 'backend:--protocol 6 minimize 0xabc123' "$LOG"
grep -Fqx 'backend:--protocol 6 window-action maximized-toggle 0xabc123' "$LOG"
grep -Fqx 'backend:--protocol 6 window-action close 0xabc123' "$LOG"

printf 'hyprbars action smoke ok\n'
