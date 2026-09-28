#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
LINT=$(command -v qmllint || true)
[[ -n $LINT ]] || LINT=/usr/lib/qt6/bin/qmllint
[[ -x $LINT && -d $OMARCHY_PATH/shell ]] || { echo 'Run QML checks on an Omarchy system with qmllint installed.' >&2; exit 2; }
imports=$(mktemp -d)
trap 'rm -rf -- "$imports"' EXIT
# Quickshell maps the qs URI to its shell root; reproduce that mapping for lint
# outside the recursively watched plugin source directory.
ln -s "$OMARCHY_PATH/shell" "$imports/qs"
# Host APIs expose QtObject/var facades with dynamic members; QProcess::ExitStatus
# is absent from the installed Quickshell qmltypes. Keep these diagnostics as
# informational; all other warnings (including syntax/import failures) fail.
"$LINT" -W 0 --missing-property info --signal-handler-parameters info -I "$imports" \
  "$ROOT/Spaces.qml" "$ROOT/SpacesService.qml" "$ROOT/WindowMenu.qml"
