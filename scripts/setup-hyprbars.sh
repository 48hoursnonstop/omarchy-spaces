#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OFFICIAL_REPO=https://github.com/hyprwm/hyprland-plugins
REPO_NAME=hyprland-plugins
HYPRBARS_NAME=hyprbars
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_ENTRY="$HYPR_DIR/hyprland.lua"
HYPR_CONFIG="$HYPR_DIR/spaces-hyprbars.lua"
HELPER_DEST="$XDG_DATA_HOME/$PLUGIN_ID/bin/spaces-hyprbars-action"
STATE_DIR="$XDG_STATE_HOME/$PLUGIN_ID"
OWNERSHIP="$STATE_DIR/hyprbars-ownership.env"
BEGIN_MARKER='-- >>> tornikegomareli.spaces:hyprbars >>>'
END_MARKER='-- <<< tornikegomareli.spaces:hyprbars <<<'
MANAGED_MARKER='-- tornikegomareli.spaces managed Hyprbars config v1'

strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;]*[mK]//g'
}

hyprpm_list_clean() {
  hyprpm list 2>/dev/null | strip_ansi
}

repo_present() {
  hyprpm_list_clean | grep -Fq "Repository $REPO_NAME "
}

hyprbars_enabled() {
  hyprpm_list_clean | awk '
    /│ Plugin hyprbars$/ { seen=1; next }
    seen && /enabled:/ { exit($0 ~ /true/ ? 0 : 1) }
    END { if (!seen) exit 1 }
  '
}

hyprbars_loaded() {
  hyprctl plugin list 2>/dev/null | grep -qi 'hyprbars'
}

repo_has_enabled_plugins() {
  hyprpm_list_clean | awk -v repo="$REPO_NAME" '
    index($0, "Repository " repo " ") { inrepo=1; next }
    /Repository .* \(by .*\):/ { inrepo=0 }
    inrepo && /enabled:[[:space:]]*true/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

state_flag() {
  local key=$1 default=${2:-0}
  [[ -f $OWNERSHIP ]] || { printf '%s\n' "$default"; return; }
  local value
  value=$(sed -n "s/^${key}=//p" "$OWNERSHIP" | tail -1)
  [[ $value == 0 || $value == 1 ]] || { echo "Invalid Hyprbars ownership field: $key" >&2; return 2; }
  printf '%s\n' "$value"
}

hook_state() {
  [[ -f $HYPR_ENTRY ]] || { printf 'absent\n'; return; }
  local b e
  b=$(grep -Fxc -- "$BEGIN_MARKER" "$HYPR_ENTRY" || true)
  e=$(grep -Fxc -- "$END_MARKER" "$HYPR_ENTRY" || true)
  if [[ $b == 0 && $e == 0 ]]; then printf 'absent\n'
  elif [[ $b == 1 && $e == 1 ]] && awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { start=NR }
    $0 == end { stop=NR }
    END { exit(!(start > 0 && stop > start)) }
  ' "$HYPR_ENTRY"; then printf 'present\n'
  else printf 'malformed\n'
  fi
}

remove_hook() {
  [[ -f $HYPR_ENTRY ]] || return 0
  local hs
  hs=$(hook_state)
  [[ $hs == absent ]] && return 0
  [[ $hs == present ]] || { echo "Refusing to edit malformed Hyprbars hook in $HYPR_ENTRY" >&2; return 2; }

  local tmp
  tmp=$(mktemp "$HYPR_DIR/.tornikegomareli.spaces-hyprland.lua.XXXXXX")
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$HYPR_ENTRY" > "$tmp"
  chmod --reference="$HYPR_ENTRY" "$tmp"
  mv -f "$tmp" "$HYPR_ENTRY"
}

add_hook() {
  local hs
  hs=$(hook_state)
  [[ $hs == present ]] && return 1
  [[ $hs == absent ]] || { echo "Refusing to edit malformed Hyprbars hook in $HYPR_ENTRY" >&2; return 2; }

  cat >> "$HYPR_ENTRY" <<EOF_HOOK

$BEGIN_MARKER
do
  local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
  local path = config .. "/hypr/spaces-hyprbars.lua"
  local file = io.open(path, "r")
  if file then
    file:close()
    dofile(path)
  end
end
$END_MARKER
EOF_HOOK
  return 0
}

other_hyprbars_config_exists() {
  [[ -d $HYPR_DIR ]] || return 1
  python3 - "$HYPR_DIR" "$HYPR_CONFIG" "$BEGIN_MARKER" "$END_MARKER" <<'PY'
from pathlib import Path
import sys
root, managed, begin, end = sys.argv[1:]
for path in Path(root).rglob('*.lua'):
    if path == Path(managed):
        continue
    text = path.read_text()
    if begin in text and end in text:
        a, tail = text.split(begin, 1)
        text = a + tail.split(end, 1)[1]
    if 'hyprbars' in text:
        sys.exit(0)
sys.exit(1)
PY
}

check_requirements() {
  local missing=()
  local cmd

  # Runtime-only refreshes should not require a compiler toolchain after the
  # official plugin is already installed, enabled and loaded.
  for cmd in hyprctl hyprpm jq python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if ((${#missing[@]} == 0)) && { ! repo_present || ! hyprbars_enabled || ! hyprbars_loaded; }; then
    for cmd in git cpio cmake meson gcc make; do
      command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
  fi

  if ((${#missing[@]})); then
    printf 'Missing required command(s): %s\n' "${missing[*]}" >&2
    echo 'Install the missing build/runtime dependencies yourself, then rerun this script.' >&2
    exit 2
  fi
  [[ -f $HYPR_ENTRY ]] || { echo "Missing Omarchy user Hyprland entrypoint: $HYPR_ENTRY" >&2; exit 2; }
}

status_mode() {
  printf 'hyprpm: %s\n' "$(command -v hyprpm >/dev/null 2>&1 && echo available || echo missing)"
  if command -v hyprpm >/dev/null 2>&1; then
    printf 'official repo: %s\n' "$(repo_present && echo present || echo absent)"
    printf 'hyprbars enabled: %s\n' "$(hyprbars_enabled && echo yes || echo no)"
  fi
  printf 'hyprbars loaded: %s\n' "$(hyprbars_loaded && echo yes || echo no)"
  printf 'managed config: %s\n' "$([[ -f $HYPR_CONFIG ]] && grep -Fq -- "$MANAGED_MARKER" "$HYPR_CONFIG" && echo present || echo absent)"
  printf 'managed hook: %s\n' "$(hook_state)"
  printf 'ownership state: %s\n' "$([[ -f $OWNERSHIP ]] && echo present || echo absent)"
}

remove_mode() {
  local enabled_owned repo_owned
  enabled_owned=$(state_flag PLUGIN_ENABLED_BY_PROJECT 0)
  repo_owned=$(state_flag REPO_ADDED_BY_PROJECT 0)
  if ((enabled_owned || repo_owned)) && ! command -v hyprpm >/dev/null; then
    echo 'hyprpm is required to remove the Hyprbars resources installed by Spaces.' >&2
    exit 2
  fi

  if [[ $(hook_state) == malformed ]]; then
    echo "Refusing removal because the managed hook markers are malformed in $HYPR_ENTRY" >&2
    exit 3
  fi

  if [[ -f $HYPR_CONFIG ]]; then
    grep -Fq -- "$MANAGED_MARKER" "$HYPR_CONFIG" || { echo "Refusing to remove an unrecognized file: $HYPR_CONFIG" >&2; exit 3; }
  fi
  remove_hook
  rm -f -- "$HYPR_CONFIG"
  rm -f -- "$HELPER_DEST"

  hyprctl reload >/dev/null

  if command -v hyprpm >/dev/null 2>&1 && [[ $enabled_owned == 1 ]]; then
    if other_hyprbars_config_exists; then
      echo 'Hyprbars remains enabled because other ~/.config/hypr configuration references it.' >&2
    elif hyprbars_enabled; then
      hyprpm disable "$HYPRBARS_NAME"
      hyprpm reload >/dev/null
    fi
  fi

  if command -v hyprpm >/dev/null 2>&1 && [[ $repo_owned == 1 ]] && repo_present; then
    if repo_has_enabled_plugins; then
      echo 'Official hyprland-plugins repository remains installed because another plugin is enabled.' >&2
    else
      hyprpm remove "$REPO_NAME"
    fi
  fi

  hyprctl reload >/dev/null
  local errors
  errors=$(hyprctl configerrors)
  if [[ -n $errors ]]; then
    echo 'Hyprland reports config errors after Hyprbars integration removal:' >&2
    printf '%s\n' "$errors" >&2
    exit 4
  fi
  rm -f -- "$OWNERSHIP"
  rmdir "$STATE_DIR" 2>/dev/null || true

  echo 'Spaces Hyprbars integration removed.'
}

preflight() {
  check_requirements

  if other_hyprbars_config_exists; then
    echo 'Another Hyprbars configuration is present. Remove its integration before enabling Spaces titlebar buttons.' >&2
    exit 3
  fi

  if [[ -f $HYPR_CONFIG ]] && ! grep -Fq -- "$MANAGED_MARKER" "$HYPR_CONFIG"; then
    echo "Refusing to overwrite an unrecognized file: $HYPR_CONFIG" >&2
    exit 3
  fi
  [[ $(hook_state) != malformed ]] || { echo "Managed hook markers are malformed in $HYPR_ENTRY" >&2; exit 3; }
}

save_ownership() {
  local repo=$1 plugin=$2
  local temporary
  temporary=$(mktemp "$STATE_DIR/.hyprbars-ownership.XXXXXX")
  printf 'SCHEMA_VERSION=1\nREPO_ADDED_BY_PROJECT=%s\nPLUGIN_ENABLED_BY_PROJECT=%s\nCONFIG_INSTALLED_BY_PROJECT=1\nHOOK_INSTALLED_BY_PROJECT=1\n' "$repo" "$plugin" > "$temporary"
  chmod 0600 "$temporary"
  mv -f -- "$temporary" "$OWNERSHIP"
}

setup_mode() {
  preflight

  mkdir -p "$STATE_DIR" "$(dirname "$HELPER_DEST")"

  local repo_was_present=0 plugin_was_enabled=0
  repo_present && repo_was_present=1
  hyprbars_enabled && plugin_was_enabled=1

  local prior_repo_owned prior_plugin_owned
  prior_repo_owned=$(state_flag REPO_ADDED_BY_PROJECT 0)
  prior_plugin_owned=$(state_flag PLUGIN_ENABLED_BY_PROJECT 0)

  local added_repo_run=0 enabled_plugin_run=0 hook_added_run=0 config_existed=0 helper_existed=0
  local config_backup helper_backup
  config_backup=$(mktemp)
  helper_backup=$(mktemp)
  [[ -f $HYPR_CONFIG ]] && { config_existed=1; cp -p "$HYPR_CONFIG" "$config_backup"; }
  [[ -f $HELPER_DEST ]] && { helper_existed=1; cp -p "$HELPER_DEST" "$helper_backup"; }

  rollback() {
    local code=$?
    local cleanup_ok=true
    trap - ERR
    echo 'Hyprbars setup failed; rolling back only Spaces changes.' >&2

    if ((hook_added_run)); then remove_hook || cleanup_ok=false; fi
    if ((config_existed)); then cp -p "$config_backup" "$HYPR_CONFIG"; else rm -f -- "$HYPR_CONFIG"; fi
    if ((helper_existed)); then cp -p "$helper_backup" "$HELPER_DEST"; else rm -f -- "$HELPER_DEST"; fi

    if ((enabled_plugin_run)); then
      hyprpm disable "$HYPRBARS_NAME" >/dev/null 2>&1 || cleanup_ok=false
      hyprpm reload >/dev/null 2>&1 || cleanup_ok=false
    fi
    if ((added_repo_run)); then
      hyprpm remove "$REPO_NAME" >/dev/null 2>&1 || cleanup_ok=false
    fi
    hyprctl reload >/dev/null 2>&1 || cleanup_ok=false
    if $cleanup_ok; then
      if ((prior_repo_owned || prior_plugin_owned || config_existed)); then
        save_ownership "$prior_repo_owned" "$prior_plugin_owned"
      else
        rm -f -- "$OWNERSHIP"
      fi
    fi
    rm -f "$config_backup" "$helper_backup"
    exit "$code"
  }
  trap rollback ERR

  # Official hyprpm manages ABI-matched headers and commit pins for the running Hyprland.
  # A healthy already-loaded install does not need a full repository/header refresh
  # just to replace our managed Lua/helper files.
  if ((repo_was_present == 0 || plugin_was_enabled == 0)) || ! hyprbars_loaded; then
    hyprpm update
  fi

  if ((repo_was_present == 0)); then
    added_repo_run=1
    save_ownership 1 "$prior_plugin_owned"
    hyprpm add "$OFFICIAL_REPO"
  fi

  if ((plugin_was_enabled == 0)); then
    enabled_plugin_run=1
    save_ownership "$((prior_repo_owned || added_repo_run))" 1
    hyprpm enable "$HYPRBARS_NAME"
  fi

  hyprpm reload
  hyprbars_loaded || { echo 'hyprpm completed, but Hyprbars is not present in hyprctl plugin list.' >&2; false; }

  install -m 0755 "$ROOT/scripts/hyprbars-action.sh" "$HELPER_DEST"
  install -m 0644 "$ROOT/hyprbars/spaces-hyprbars.lua" "$HYPR_CONFIG"
  if add_hook; then hook_added_run=1; fi

  hyprctl reload >/dev/null
  sleep 0.2

  hyprbars_loaded || { echo 'Hyprbars unloaded after config reload.' >&2; false; }
  local errors
  errors=$(hyprctl configerrors)
  [[ -z $errors ]] || { echo 'Hyprland config errors after Hyprbars setup:' >&2; printf '%s\n' "$errors" >&2; false; }

  local repo_owned=$prior_repo_owned plugin_owned=$prior_plugin_owned
  ((added_repo_run)) && repo_owned=1
  ((enabled_plugin_run)) && plugin_owned=1

  save_ownership "$repo_owned" "$plugin_owned"

  trap - ERR
  rm -f "$config_backup" "$helper_backup"

  echo 'Hyprbars integration enabled through official hyprpm.'
  echo "Managed config: $HYPR_CONFIG"
  echo 'Buttons: minimize, maximize/restore, close. Double-click titlebar: toggle maximized.'
}

case "${1:-}" in
  ''|--setup) setup_mode ;;
  --remove) remove_mode ;;
  --status) status_mode ;;
  --check) preflight ;;
  -h|--help)
    echo "usage: ${0##*/} [--setup|--remove|--status|--check]"
    ;;
  *)
    echo "usage: ${0##*/} [--setup|--remove|--status]" >&2
    exit 2
    ;;
esac
