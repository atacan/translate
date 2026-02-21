#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VERSION="${1:?Usage: scripts/release/update-formula.sh VERSION TAG}"
TAG="${2:?Usage: scripts/release/update-formula.sh VERSION TAG}"

require_cmd gh
require_cmd git
require_checksum_tool
ensure_archives_present "$VERSION"

sha_macos_arm64="$(compute_sha "${ARCHIVE_DIR}/${NAME}-${VERSION}-macos-arm64.tar.gz")"
sha_macos_amd64="$(compute_sha "${ARCHIVE_DIR}/${NAME}-${VERSION}-macos-amd64.tar.gz")"
sha_linux_arm64="$(compute_sha "${ARCHIVE_DIR}/${NAME}-${VERSION}-linux-arm64.tar.gz")"
sha_linux_amd64="$(compute_sha "${ARCHIVE_DIR}/${NAME}-${VERSION}-linux-amd64.tar.gz")"

formula_class="$(class_name "$NAME")"

tap_dir="$(mktemp -d)"
trap 'rm -rf "$tap_dir"' EXIT

echo "==> Cloning tap ${TAP_REPO}"
if [[ -n "${GH_TOKEN:-}" ]]; then
  git clone "https://x-access-token:${GH_TOKEN}@github.com/${TAP_REPO}.git" "$tap_dir" --depth 1
else
  gh repo clone "$TAP_REPO" "$tap_dir" -- --depth 1
fi
mkdir -p "${tap_dir}/Formula"

cat > "${tap_dir}/Formula/${NAME}.rb" <<RUBY
class ${formula_class} < Formula
  desc "Translate text and files with configurable providers and prompt presets"
  homepage "https://github.com/${REPO}"
  version "${VERSION}"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/${REPO}/releases/download/${TAG}/${NAME}-${VERSION}-macos-arm64.tar.gz"
      sha256 "${sha_macos_arm64}"
    end
    on_intel do
      url "https://github.com/${REPO}/releases/download/${TAG}/${NAME}-${VERSION}-macos-amd64.tar.gz"
      sha256 "${sha_macos_amd64}"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/${REPO}/releases/download/${TAG}/${NAME}-${VERSION}-linux-arm64.tar.gz"
      sha256 "${sha_linux_arm64}"
    end
    on_intel do
      url "https://github.com/${REPO}/releases/download/${TAG}/${NAME}-${VERSION}-linux-amd64.tar.gz"
      sha256 "${sha_linux_amd64}"
    end
  end

  def install
    bin.install "${NAME}"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/${NAME} --version")
  end
end
RUBY

git -C "$tap_dir" add "Formula/${NAME}.rb"
if git -C "$tap_dir" diff --cached --quiet; then
  echo "==> Formula unchanged; skipping tap commit"
  exit 0
fi

if ! git -C "$tap_dir" config --get user.name >/dev/null; then
  git -C "$tap_dir" config user.name "release-bot"
fi
if ! git -C "$tap_dir" config --get user.email >/dev/null; then
  git -C "$tap_dir" config user.email "release-bot@users.noreply.github.com"
fi

git -C "$tap_dir" commit -m "${NAME} ${VERSION}"
git -C "$tap_dir" push origin main

echo "==> Tap formula updated: Formula/${NAME}.rb"
