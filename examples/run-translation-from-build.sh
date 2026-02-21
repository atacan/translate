#!/usr/bin/env bash
set -euo pipefail

# Resolve repository root from this script location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Allow override when needed.
TRANSLATE_BIN="${TRANSLATE_BIN:-}"

if [[ -z "${TRANSLATE_BIN}" ]]; then
  candidates=(
    "${REPO_ROOT}/build/translate"
    "${REPO_ROOT}/build/debug/translate"
    "${REPO_ROOT}/build/release/translate"
    "${REPO_ROOT}/.build/debug/translate"
    "${REPO_ROOT}/.build/release/translate"
    "${REPO_ROOT}/.build/arm64-apple-macosx/debug/translate"
    "${REPO_ROOT}/.build/arm64-apple-macosx/release/translate"
    "${REPO_ROOT}/.build/x86_64-apple-macosx/debug/translate"
    "${REPO_ROOT}/.build/x86_64-apple-macosx/release/translate"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      TRANSLATE_BIN="${candidate}"
      break
    fi
  done
fi

if [[ -z "${TRANSLATE_BIN}" || ! -x "${TRANSLATE_BIN}" ]]; then
  echo "Could not find the translate binary in build outputs." >&2
  echo "Build first (for example: swift build), or set TRANSLATE_BIN=/path/to/translate" >&2
  exit 1
fi

INPUT_TEXT="${1:-Merhaba dunya}"
TARGET_LANG="${2:-en}"
PROVIDER="${3:-apple-translate}"

# Default uses --dry-run so this script can be executed without API credentials.
exec "${TRANSLATE_BIN}" \
  --text \
  --provider "${PROVIDER}" \
  --from auto \
  --to "${TARGET_LANG}" \
  --dry-run \
  "${INPUT_TEXT}"
