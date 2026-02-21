#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

NAME="translate"
REPO="atacan/translate"
TAP_REPO="atacan/homebrew-tap"
VERSION_FILE="Sources/translate/CLI/TranslateCommand.swift"

OUTPUT_DIR="${REPO_ROOT}/output"
BIN_DIR="${OUTPUT_DIR}/binaries"
ARCHIVE_DIR="${OUTPUT_DIR}/archives"
PLATFORMS="macos-arm64 macos-amd64 linux-arm64 linux-amd64"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
}

require_checksum_tool() {
  if command -v shasum >/dev/null 2>&1; then
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    return
  fi
  echo "Error: need shasum or sha256sum in PATH." >&2
  exit 1
}

compute_sha() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  sha256sum "$path" | awk '{print $1}'
}

class_name() {
  local raw="${1:-$NAME}"
  local first rest
  first="$(printf '%s' "${raw:0:1}" | tr '[:lower:]' '[:upper:]')"
  rest="${raw:1}"
  printf '%s%s\n' "$first" "$rest"
}

ensure_clean_repo() {
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Error: working tree is dirty. Commit or stash changes first." >&2
    exit 1
  fi
}

ensure_archives_present() {
  local version="$1"
  local platform
  for platform in $PLATFORMS; do
    local archive="${ARCHIVE_DIR}/${NAME}-${version}-${platform}.tar.gz"
    if [[ ! -f "$archive" ]]; then
      echo "Error: missing archive: $archive" >&2
      exit 1
    fi
  done
}
