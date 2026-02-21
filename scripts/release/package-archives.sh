#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VERSION="${1:?Usage: scripts/release/package-archives.sh VERSION}"

mkdir -p "$ARCHIVE_DIR"

for platform in $PLATFORMS; do
  source_bin="${BIN_DIR}/${NAME}-${platform}"
  archive_path="${ARCHIVE_DIR}/${NAME}-${VERSION}-${platform}.tar.gz"

  if [[ ! -f "$source_bin" ]]; then
    echo "Error: missing binary $source_bin" >&2
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  cp "$source_bin" "${tmpdir}/${NAME}"
  chmod +x "${tmpdir}/${NAME}"
  tar -czf "$archive_path" -C "$tmpdir" "$NAME"

  if ! tar -tzf "$archive_path" | grep -qx "$NAME"; then
    echo "Error: archive contents invalid for $archive_path (expected internal file: $NAME)" >&2
    rm -rf "$tmpdir"
    exit 1
  fi

  rm -rf "$tmpdir"
  echo "    wrote: $archive_path"
done
