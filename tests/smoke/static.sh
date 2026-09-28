#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
jq -e '.schemaVersion == 1 and (.kinds | index("service")) and (.kinds | index("bar-widget")) and (.kinds | index("menu"))' "$ROOT/manifest.json" >/dev/null
jq -e '.omarchy.baseline == "4.0.4"' "$ROOT/compat/upstream.json" >/dev/null
while IFS= read -r entry; do test -f "$ROOT/$entry"; done < <(jq -r '.entryPoints[]' "$ROOT/manifest.json")
test -f "$ROOT/backend/Cargo.lock"
if grep -R -E 'parent\.parent\.shell|bar\.shell\.appLibrary' "$ROOT"/*.qml "$ROOT/qml" >/dev/null; then echo "Forbidden condition detected" >&2; exit 1; fi
for file in "$ROOT"/scripts/*.sh "$ROOT"/tests/smoke/*.sh; do bash -n "$file"; done
bash -n "$ROOT/hooks/claude-hook"
node "$ROOT/tests/model.test.js"
node "$ROOT/tests/smoke/app-matcher.test.js"
"$ROOT/tests/smoke/hyprbars-setup.test.sh"
"$ROOT/tests/smoke/hyprbars-action.test.sh"
if command -v omarchy >/dev/null; then omarchy plugin validate "$ROOT"; fi
printf 'static smoke ok\n'
