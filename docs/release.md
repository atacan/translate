## Releasing translate

This project supports both local releases (`release.sh`) and automated releases from GitHub Actions on tag push.
Both paths reuse the same scripts under `scripts/release`.

### Prerequisites

- `gh` installed and authenticated (`gh auth status`)
- Docker daemon running (required for local Linux static cross-build)
- Clean working tree on `main`
- `HOMEBREW_TAP_TOKEN` configured in GitHub Actions secrets (fine-grained token with `Contents: write` on `atacan/homebrew-tap`)

### Local release

Run from repository root:

```bash
./release.sh X.Y.Z
```

What it does:

1. Bumps CLI version in `Sources/translate/CLI/TranslateCommand.swift`
2. Builds macOS arm64/amd64 binaries
3. Builds Linux arm64/amd64 static binaries via Dockerfile (`scripts/release/Dockerfile.linux`)
4. Packages archives with internal binary name exactly `translate`
5. Commits version bump, tags `vX.Y.Z`, pushes `main` + tag
6. Creates GitHub release with generated notes
7. Updates `Formula/translate.rb` in `atacan/homebrew-tap`

### Recovery mode (`--formula-only`)

If release artifacts already exist but formula update failed:

```bash
./release.sh --formula-only X.Y.Z
```

This downloads archives from the existing tag release and only updates the Homebrew formula.

### Linux-only build and runtime checks

Build Linux binaries only:

```bash
scripts/release/build-linux.sh
```

Validate those binaries in Fedora containers (amd64 + arm64):

```bash
scripts/release/test-linux-fedora.sh
```

### Automated release (CI)

Workflow: `.github/workflows/release.yml`

Trigger:

- Push tag `v*`

Build jobs:

- `build-macos` (`macos-14`): runs `scripts/release/build-macos.sh` (produces arm64 + amd64 binaries)
- `build-linux` (`ubuntu-latest`): runs `scripts/release/build-linux.sh` (produces arm64 + amd64 static binaries)

Release job:

1. Downloads binaries from build jobs
2. Packages archives via `scripts/release/package-archives.sh`
3. Creates GitHub release with generated notes (or downloads existing archives on rerun)
4. Updates Homebrew formula via `scripts/release/update-formula.sh`

### Common troubleshooting

- **Tag already exists**: use `./release.sh --formula-only X.Y.Z`.
- **Archive install fails with `No such file`**: ensure tar contains `translate`, not `translate-<platform>`.
- **Docker error `Cannot connect to the Docker daemon`**: start Docker Desktop/OrbStack and rerun.
- **Formula push fails in CI**: verify `HOMEBREW_TAP_TOKEN` has write access to `atacan/homebrew-tap`.

### Install and upgrade for users

```bash
brew tap atacan/tap
brew install atacan/tap/translate
brew upgrade translate
```
