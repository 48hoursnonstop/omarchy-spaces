#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
[[ -z $(git status --porcelain) ]] || { echo 'Commit reviewed source before packaging.' >&2; exit 2; }
id=$(jq -r .id manifest.json)
version=$(jq -r .version manifest.json)
out=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/$id/releases}
mkdir -p "$out"
out=$(realpath "$out")
archive="$out/$id-v$version.tar.gz"
git archive --format=tar --prefix="$id/" HEAD | gzip -n > "$archive"
(cd "$out" && sha256sum "${archive##*/}" > "${archive##*/}.sha256")
printf '%s\n' "$archive" "$archive.sha256"
