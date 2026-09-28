#!/usr/bin/env bash
set -uo pipefail
PLUGIN_ID=tornikegomareli.spaces
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN="${XDG_DATA_HOME:-$HOME/.local/share}/$PLUGIN_ID/bin/spaces-backend"
OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
pre_enable=false
case ${1:-} in
  '') ;;
  --pre-enable) pre_enable=true ;;
  *) echo 'usage: doctor.sh [--pre-enable]' >&2; exit 2 ;;
esac
ok=1
check() { printf '%-30s %s\n' "$1" "$2"; }
pass() { check "$1" ok; }
fail() { check "$1" "FAIL: $2"; ok=0; }
warn() { check "$1" "WARN: $2"; }
for tool in jq omarchy omarchy-shell hyprctl sha256sum; do
  command -v "$tool" >/dev/null || { fail "$tool" 'required command missing'; exit 2; }
done
check plugin "$PLUGIN_ID"
version=$(pacman -Q omarchy 2>/dev/null | awk '{print $2}')
check Omarchy "${version:-unavailable}"
[[ $version == 4.0.4-* ]] || warn compatibility 'reviewed Omarchy baseline is 4.0.4'
hypr_version=$(hyprctl version 2>&1)
if [[ $hypr_version == 'Hyprland 0.56.'* ]]; then check Hyprland "${hypr_version%%$'\n'*}"; else fail Hyprland "$hypr_version"; fi
check Quickshell "$(qs --version 2>&1)"
check kernel "$(uname -r)"
check 'kernel packages' "$(pacman -Q linux linux-lts linux-omarchy 2>/dev/null | tr '\n' ' ')"
if omarchy-shell shell ping >/dev/null 2>&1; then pass 'shell IPC'; else fail 'shell IPC' unavailable; fi
if omarchy plugin validate "$ROOT"; then pass manifest; else fail manifest rejected; fi
for spec in 'PluginShellApi.qml:function serviceFor(id)' 'PluginAppLibraryApi.qml:function sortedEntries(query)' 'PluginAppLibraryApi.qml:function iconSource(icon)'; do
  file=${spec%%:*}; pattern=${spec#*:}
  if grep -Fq "$pattern" "$OMARCHY_PATH/shell/services/$file"; then pass "$pattern"; else fail "$pattern" 'public capability missing'; fi
done
if [[ -x $BIN ]]; then
  check backend "$BIN"
  check sha256 "$(sha256sum "$BIN" | awk '{print $1}')"
  if v=$("$BIN" version-json) && jq -e '.ok == true and .protocolVersion == 6 and .stateSchemaVersion == 1' <<<"$v" >/dev/null; then
    check 'backend version' "$v"
  else fail 'backend version' "Backend update required: $ROOT/scripts/build-backend.sh"; fi
  if report=$("$BIN" --protocol 6 doctor-json) && jq -e '.ok == true' <<<"$report" >/dev/null; then
    check 'restore state' "$report"
  else fail 'restore state' "${report:-no valid response}; run backend recover"; fi
else fail backend "missing; run $ROOT/scripts/build-backend.sh"; fi
if errors=$(hyprctl configerrors); then
  if [[ -z $errors ]]; then pass 'Hyprland config'; else fail 'Hyprland config' "$errors"; fi
else fail 'Hyprland config' 'query failed'; fi
if plugins=$(hyprctl plugin list); then check 'compositor plugins' "${plugins:-none}"; else fail 'compositor plugins' 'query failed'; fi
if command -v hyprpm >/dev/null; then
  check hyprpm "$(hyprpm list 2>&1)"
elif ! $pre_enable; then fail Hyprbars 'hyprpm not installed'; fi
hypr_config="$CONFIG_HOME/hypr/spaces-hyprbars.lua"
if [[ -f $hypr_config ]]; then
  helper="${XDG_DATA_HOME:-$HOME/.local/share}/$PLUGIN_ID/bin/spaces-hyprbars-action"
  if [[ -x $helper ]]; then pass 'Hyprbars helper'; else fail 'Hyprbars helper' missing; fi
  if [[ $plugins != *hyprbars* ]] && ! $pre_enable; then fail Hyprbars 'managed decoration is not loaded'; fi
  for marker in '-- >>> tornikegomareli.spaces:hyprbars >>>' '-- <<< tornikegomareli.spaces:hyprbars <<<'; do
    [[ $(grep -Fxc -- "$marker" "$CONFIG_HOME/hypr/hyprland.lua") == 1 ]] || fail 'Hyprbars hook' 'missing or duplicated marker'
  done
elif ! $pre_enable; then fail Hyprbars 'managed configuration missing'; fi
if [[ $pre_enable == false ]]; then
  if catalog=$(omarchy plugin list --json) && jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' <<<"$catalog" >/dev/null; then
    pass enabled
  else fail enabled 'plugin is disabled or not registered'; fi
  config="$CONFIG_HOME/omarchy/shell.json"
  if jq -e --arg id "$PLUGIN_ID" '(.bar.id // "omarchy.bar") == "omarchy.bar" and any(.bar.layout[]?[]?; .id == $id)' "$config" >/dev/null; then
    pass 'built-in bar / placement'
  else fail placement 'expected widget in built-in omarchy.bar'; fi
  if status=$(omarchy-shell tornikegomareli.spaces status) && jq -e '.backendHealthy and .protocolCompatible and .appLibraryHealthy' <<<"$status" >/dev/null; then
    check service "$status"
  else fail service "${status:-IPC unavailable}; check AppLibrary capability and backend"; fi
else check runtime 'pre-enable: service/placement checks deferred'; fi
exit $((ok ? 0 : 1))
