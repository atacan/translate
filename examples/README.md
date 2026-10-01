# Runnable prompt examples

These 31 independent walkthroughs target this source tree and its built executable. The demonstrated prompt and catalog behavior is available starting with version 0.4.0. Every command explicitly selects one local config with `--config`; run it after changing into that example directory. No local config discovery or config merging is involved.

From the repository root, build the branch and put its executable on PATH:

```sh
swift build
export PATH="$PWD/.build/debug:$PATH"
```

Each README lists its files, runnable dry-run commands, selection/origin explanation, exit status, and complete captured stdout/stderr. English to French is pinned with CLI flags, and provider/model are pinned unless a walkthrough tests preset metadata or DeepL. No config relies on home-directory files or environment selection. No real keys are included. Dry-run bypasses credential requirements, makes no API calls, writes no translation files, and asks for no confirmation.

Expected output uses `<example-directory>` for the absolute path of the directory you entered. The rest of every prompt block is literal, including blank lines. Prompt files include their trailing newline; the dry-run printer adds its own separators, so a file template can produce an extra blank line before the next section. Output snapshots include all pending catalog requests: every command has at most three. The input preview is separate from the user message and is not an additional message.

Prompt fields resolve independently: CLI inline/@file, selected preset inline, selected preset file, then original built-in fallback. Shadowing a built-in falls back to that built-in; a new custom preset falls back to original general. Config-relative prompt files use the config directory; CLI @files use the current working directory. Preset selection is CLI --preset, then config defaults.preset, then configured default general. Catalog-only input can instead select implicit xcode-strings when neither an explicit selector nor customization of the configured default is present. Mixed input resolves text and catalog preset choices separately.

## Walkthroughs

- [01-text-defaults: Text with built-in defaults](01-text-defaults/README.md)
- [02-builtin-preset: Select a built-in preset](02-builtin-preset/README.md)
- [03-config-default-preset: Select the config default preset](03-config-default-preset/README.md)
- [04-custom-inline-preset: Use inline preset templates](04-custom-inline-preset/README.md)
- [05-custom-file-preset: Use preset prompt files](05-custom-file-preset/README.md)
- [06-config-relative-paths: Resolve files relative to nested config](06-config-relative-paths/README.md)
- [07-partial-builtin-override: Override one built-in field](07-partial-builtin-override/README.md)
- [08-partial-custom-preset: Fall back from a partial custom preset](08-partial-custom-preset/README.md)
- [09-inline-beats-preset-file: Inline preset fields win over files](09-inline-beats-preset-file/README.md)
- [10-cli-inline-prompts: CLI inline prompts win](10-cli-inline-prompts/README.md)
- [11-cli-file-prompts: CLI prompt files win](11-cli-file-prompts/README.md)
- [12-cli-system-only: Override only the system field](12-cli-system-only/README.md)
- [13-cli-user-only: Override only the user field](13-cli-user-only/README.md)
- [14-cli-file-over-config-file: Compare CLI and config file path bases](14-cli-file-over-config-file/README.md)
- [15-cli-preset-over-default: CLI preset wins over config default](15-cli-preset-over-default/README.md)
- [16-explicit-config-selection: Choose one local config explicitly](16-explicit-config-selection/README.md)
- [17-catalog-defaults: Use the implicit catalog preset](17-catalog-defaults/README.md)
- [18-catalog-explicit-general: Explicitly select general for a catalog](18-catalog-explicit-general/README.md)
- [19-catalog-customized-general: Customize the catalog default general](19-catalog-customized-general/README.md)
- [20-catalog-customized-xcode: Customize xcode-strings with files](20-catalog-customized-xcode/README.md)
- [21-catalog-overrides-and-context: Render catalog metadata and context](21-catalog-overrides-and-context/README.md)
- [22-catalog-metadata-only-preset: Metadata customization affects preset selection](22-catalog-metadata-only-preset/README.md)
- [23-mixed-text-and-catalog: Resolve mixed input prompts independently](23-mixed-text-and-catalog/README.md)
- [24-literal-placeholder-content: Substitute placeholders once](24-literal-placeholder-content/README.md)
- [25-invalid-prompts: Validate custom prompt pairs](25-invalid-prompts/README.md)
- [26-config-diagnostics: Diagnose explicitly selected configs](26-config-diagnostics/README.md)
- [27-unused-prompt-files: Skip files that cannot win](27-unused-prompt-files/README.md)
- [28-catalog-pending-selection: Select pending catalog segments](28-catalog-pending-selection/README.md)
- [29-catalog-retranslation: Retranslate completed catalog segments](29-catalog-retranslation/README.md)
- [30-catalog-source-and-format: Keep catalog routing and source authoritative](30-catalog-source-and-format/README.md)
- [31-promptless-provider: Skip prompts for a promptless provider](31-promptless-provider/README.md)

## Optional live execution

The documented commands are previews. To translate, deliberately remove `--dry-run` from a command after configuring that provider’s credentials/service. Live requests may cost money and produce different wording on each run. A single explicitly named file or inline text outputs to stdout by default; mixed/multiple files use suffixed outputs, unless output flags change that plan. A catalog result remains catalog JSON. Use `--output result.xcstrings` for a single catalog if you want to save a separate result; `--in-place` overwrites the original and is an explicit choice.

Dry-run demonstrates selection, warnings, and rendered inputs. It does not test model compliance, output validity, or a failed response. Catalog execution validates format arguments and preserves prior values for failed selected segments; preservation and rejection are execution behavior, not guaranteed model output or effects of a preview. No live calls were used to create these walkthroughs.
