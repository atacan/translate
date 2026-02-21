#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_cmd docker
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running." >&2
  exit 1
fi

AMD64_BIN="${BIN_DIR}/${NAME}-linux-amd64"
ARM64_BIN="${BIN_DIR}/${NAME}-linux-arm64"

for bin in "$AMD64_BIN" "$ARM64_BIN"; do
  if [[ ! -f "$bin" ]]; then
    echo "Error: missing Linux binary: $bin" >&2
    echo "Run scripts/release/build-linux.sh first." >&2
    exit 1
  fi
  chmod +x "$bin"
done

echo "==> Testing linux/amd64 binary in Fedora"
docker run --rm --platform linux/amd64 \
  -v "$AMD64_BIN":/translate:ro \
  fedora:latest \
  /translate --version

echo "==> Testing linux/arm64 binary in Fedora"
docker run --rm --platform linux/arm64 \
  -v "$ARM64_BIN":/translate:ro \
  fedora:latest \
  /translate --version

echo "==> Fedora runtime check passed for both Linux binaries"
