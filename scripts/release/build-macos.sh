#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: scripts/release/build-macos.sh must be run on macOS." >&2
  exit 1
fi

require_cmd swift
mkdir -p "$BIN_DIR"

build_one() {
  local arch="$1"
  local suffix="$2"
  local target="${BIN_DIR}/${NAME}-macos-${suffix}"

  echo "==> Building macOS ${suffix} (${arch})"
  swift build -c release --arch "$arch"

  local bin_path
  bin_path="$(swift build -c release --arch "$arch" --show-bin-path)/${NAME}"
  cp "$bin_path" "$target"
  chmod +x "$target"

  if command -v strip >/dev/null 2>&1; then
    strip "$target" || true
  fi

  "$target" --version >/dev/null
  echo "    wrote: $target"
}

build_one arm64 arm64
build_one x86_64 amd64

if command -v lipo >/dev/null 2>&1; then
  echo "==> Built macOS binaries"
  for suffix in arm64 amd64; do
    local_path="${BIN_DIR}/${NAME}-macos-${suffix}"
    echo "    $(basename "$local_path"): $(lipo -archs "$local_path")"
  done
fi
