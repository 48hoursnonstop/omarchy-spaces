#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config/hypr" "$TMP/bin" "$TMP/mock"
printf '%s\n' '-- test Omarchy hyprland.lua' > "$TMP/home/.config/hypr/hyprland.lua"

cat > "$TMP/bin/hyprpm" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  list)
    if [[ -f $MOCK_STATE/repo ]]; then
      echo 'Repository hyprland-plugins (by hyprwm):'
      echo '  │ Plugin hyprbars'
      if [[ -f $MOCK_STATE/enabled ]]; then echo '  └─ enabled: true'; else echo '  └─ enabled: false'; fi
    fi
    ;;
  update) ;;
  add) touch "$MOCK_STATE/repo" ;;
  enable) touch "$MOCK_STATE/enabled" ;;
  disable) rm -f "$MOCK_STATE/enabled" "$MOCK_STATE/loaded" ;;
  reload)
    if [[ -f $MOCK_STATE/enabled ]]; then touch "$MOCK_STATE/loaded"; else rm -f "$MOCK_STATE/loaded"; fi
    ;;
  remove) rm -f "$MOCK_STATE/repo" "$MOCK_STATE/enabled" "$MOCK_STATE/loaded" ;;
  *) exit 2 ;;
esac
MOCK

cat > "$TMP/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  [[ -f $MOCK_STATE/loaded ]] && echo 'name: hyprbars'
elif [[ ${1:-} == reload ]]; then
  :
elif [[ ${1:-} == configerrors ]]; then
  :
else
  :
fi
MOCK

cat > "$TMP/bin/meson" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TMP/bin/hyprpm" "$TMP/bin/hyprctl" "$TMP/bin/meson"

export XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_DATA_HOME="$TMP/data"
export XDG_STATE_HOME="$TMP/state"
export MOCK_STATE="$TMP/mock"
export PATH="$TMP/bin:$PATH"

"$ROOT/scripts/setup-hyprbars.sh" >/dev/null

test -f "$XDG_CONFIG_HOME/hypr/spaces-hyprbars.lua"
test -x "$XDG_DATA_HOME/tornikegomareli.spaces/bin/spaces-hyprbars-action"
test -f "$XDG_STATE_HOME/tornikegomareli.spaces/hyprbars-ownership.env"
grep -Fq 'REPO_ADDED_BY_PROJECT=1' "$XDG_STATE_HOME/tornikegomareli.spaces/hyprbars-ownership.env"
grep -Fq 'PLUGIN_ENABLED_BY_PROJECT=1' "$XDG_STATE_HOME/tornikegomareli.spaces/hyprbars-ownership.env"
[[ $(grep -Fc -- '-- >>> tornikegomareli.spaces:hyprbars >>>' "$XDG_CONFIG_HOME/hypr/hyprland.lua") == 1 ]]

# Idempotent runtime-only rerun must not need the build toolchain, duplicate
# the import, or lose ownership. `meson` was only required for the first install.
rm -f "$TMP/bin/meson"
"$ROOT/scripts/setup-hyprbars.sh" >/dev/null
[[ $(grep -Fc -- '-- >>> tornikegomareli.spaces:hyprbars >>>' "$XDG_CONFIG_HOME/hypr/hyprland.lua") == 1 ]]
grep -Fq 'REPO_ADDED_BY_PROJECT=1' "$XDG_STATE_HOME/tornikegomareli.spaces/hyprbars-ownership.env"
grep -Fq 'PLUGIN_ENABLED_BY_PROJECT=1' "$XDG_STATE_HOME/tornikegomareli.spaces/hyprbars-ownership.env"

"$ROOT/scripts/setup-hyprbars.sh" --remove >/dev/null
if test -e "$XDG_CONFIG_HOME/hypr/spaces-hyprbars.lua"; then echo "Forbidden condition detected" >&2; exit 1; fi
if test -e "$XDG_DATA_HOME/tornikegomareli.spaces/bin/spaces-hyprbars-action"; then echo "Forbidden condition detected" >&2; exit 1; fi
if test -e "$XDG_STATE_HOME/tornikegomareli.spaces/hyprbars-ownership.env"; then echo "Forbidden condition detected" >&2; exit 1; fi
if grep -Fq -- '-- >>> tornikegomareli.spaces:hyprbars >>>' "$XDG_CONFIG_HOME/hypr/hyprland.lua"; then echo "Forbidden condition detected" >&2; exit 1; fi
if test -e "$MOCK_STATE/repo"; then echo "Forbidden condition detected" >&2; exit 1; fi

printf 'hyprbars setup smoke ok\n'
