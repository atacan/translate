#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_cmd docker
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running." >&2
  exit 1
fi

DOCKERFILE="${SCRIPT_DIR}/Dockerfile.linux"
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Error: Dockerfile not found at $DOCKERFILE" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"

echo "==> Building static Linux binaries with Docker"
DOCKER_BUILDKIT=1 docker build \
  --file "$DOCKERFILE" \
  --output "type=local,dest=${BIN_DIR}" \
  "$REPO_ROOT"

echo
echo "==> Verifying binaries exist"
for arch in amd64 arm64; do
  bin="${BIN_DIR}/${NAME}-linux-${arch}"
  if [[ ! -f "$bin" ]]; then
    echo "Error: missing built binary: $bin" >&2
    exit 1
  fi
  chmod +x "$bin"
  if command -v du >/dev/null 2>&1; then
    echo "  $(basename "$bin"): $(du -h "$bin" | awk '{print $1}')"
  else
    echo "  $(basename "$bin"): built"
  fi
done

echo
"${SCRIPT_DIR}/test-linux-fedora.sh"

echo
echo "==> Linux build and Fedora runtime tests passed"
echo "  ${BIN_DIR}/${NAME}-linux-amd64"
echo "  ${BIN_DIR}/${NAME}-linux-arm64"
