#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/release/common.sh"

FORMULA_ONLY=false
if [[ "${1:-}" == "--formula-only" ]]; then
  FORMULA_ONLY=true
  shift
fi

VERSION="${1:?Usage: ./release.sh [--formula-only] VERSION}"
TAG="v${VERSION}"

require_cmd git
require_cmd gh
require_cmd perl
require_cmd tar
require_checksum_tool

gh auth status >/dev/null 2>&1 || {
  echo "Error: gh is not authenticated. Run: gh auth login" >&2
  exit 1
}

if [[ "$FORMULA_ONLY" == false ]]; then
  ensure_clean_repo

  current_branch="$(git -C "$REPO_ROOT" branch --show-current)"
  if [[ "$current_branch" != "main" ]]; then
    echo "Error: release must run from main branch. Current branch: $current_branch" >&2
    exit 1
  fi

  if git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: local tag already exists: $TAG" >&2
    echo "Use --formula-only to update the formula from existing release archives." >&2
    exit 1
  fi

  if git -C "$REPO_ROOT" ls-remote --tags origin "refs/tags/$TAG" | grep -q "$TAG"; then
    echo "Error: remote tag already exists: $TAG" >&2
    echo "Use --formula-only to update the formula from existing release archives." >&2
    exit 1
  fi

  version_file="${REPO_ROOT}/${VERSION_FILE}"
  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' EXIT

  perl -0777 -pe 's/version: "[^"]+"/version: "'"$VERSION"'"/' "$version_file" > "$tmpfile"
  if ! grep -q "version: \"${VERSION}\"" "$tmpfile"; then
    echo "Error: failed to update version in ${VERSION_FILE}" >&2
    exit 1
  fi
  mv "$tmpfile" "$version_file"
  trap - EXIT

  echo "==> Building binaries"
  "${SCRIPT_DIR}/scripts/release/build-macos.sh"
  "${SCRIPT_DIR}/scripts/release/build-linux.sh"

  echo "==> Packaging archives"
  "${SCRIPT_DIR}/scripts/release/package-archives.sh" "$VERSION"

  echo "==> Committing and tagging"
  git -C "$REPO_ROOT" add "$VERSION_FILE"
  git -C "$REPO_ROOT" commit -m "Release ${VERSION}"
  git -C "$REPO_ROOT" tag -a "$TAG" -m "Release ${VERSION}"
  git -C "$REPO_ROOT" push origin main "$TAG"

  echo "==> Creating GitHub release"
  gh release create "$TAG" "${ARCHIVE_DIR}"/*.tar.gz \
    --repo "$REPO" \
    --title "$TAG" \
    --generate-notes
else
  echo "==> Formula-only mode: downloading existing release archives"
  mkdir -p "$ARCHIVE_DIR"
  rm -f "${ARCHIVE_DIR}"/*.tar.gz

  gh release download "$TAG" \
    --repo "$REPO" \
    --dir "$ARCHIVE_DIR" \
    --pattern '*.tar.gz'
fi

ensure_archives_present "$VERSION"

echo "==> Updating Homebrew formula"
"${SCRIPT_DIR}/scripts/release/update-formula.sh" "$VERSION" "$TAG"

echo
echo "Release complete. Install with: brew install ${TAP_REPO#*/}/${NAME}"
