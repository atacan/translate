# `translate` CLI Implementation Plan (Revision 3)

Date: 2026-02-21
Scope: execution plan from current repository state.

This revision replaces earlier planning with an ordered completion plan that proceeds on all non-DeepL work now, while keeping DeepL integration as a final unblock phase.

## Current status snapshot

Already implemented in repository (baseline to build on):
- Modular structure under `Sources/translate` for CLI, config, input, prompt, providers, execution, support.
- Core translation flow for text/stdin/files.
- Config parsing and dot-key config editing.
- Built-in presets and dry-run rendering.
- HTTP transport with retry/timeout foundation.
- `config` and `presets` subcommands.
- Initial tests in `Tests/translateTests/CoreTests.swift`.

Not complete yet (must finish):
- Exact help/UX parity with spec Section 16.
- Apple provider implementations and gating behavior.
- `.xcstrings` workflow integration with `StringCatalogKit`.
- Full warning/error message parity and scenario parity.
- Full test matrix and snapshot coverage.
- DeepL provider (blocked by package work in progress).

## Execution constraints

- Do not implement placeholder or fake DeepL behavior beyond explicit “deferred/unavailable” messaging.
- Keep macOS baseline aligned with project toolchain (`macOS 26`).
- No release claim of full Section 7 provider parity until DeepL phase is completed.

---

## Phase 1: CLI surface and help parity lock

Objective:
Make command behavior and help output deterministic and spec-aligned before adding more provider/catalog complexity.

Tasks:
1. Refactor root command model so:
   - `translate --help` shows main translation usage and options.
   - `translate help` shows subcommand index.
   - `translate config ...` and `translate presets ...` remain first-class subcommands.
2. Align option naming/help text with spec labels.
3. Ensure `--version` works at root level.

Files:
- `Sources/translate/CLI/TranslateCommand.swift`
- `Sources/translate/CLI/GlobalOptions.swift`
- `Sources/translate/translate.swift`

Validation:
- `swift run translate --help`
- `swift run translate help`
- `swift run translate --version`

Exit criteria:
- Help entry points produce stable, expected output and no routing ambiguity.

---

## Phase 2: Validation/error/warning parity hardening

Objective:
Normalize all hard errors, warnings, and exit-code mapping to spec intent.

Tasks:
1. Centralize message strings used by validation and runtime failures.
2. Ensure all flag conflicts map to exit code `2`.
3. Ensure runtime/input/provider failures map to exit code `1`.
4. Ensure non-TTY confirmation abort maps to exit code `3`.
5. Confirm warning suppression behavior with `--quiet`.
6. Enforce exact behavior for:
   - `--suffix` ignored warning in single explicit-file stdout mode.
   - `--jobs` ignored warning for non-file input.
   - custom prompt language-placeholder warning and `--no-lang` suppression.

Files:
- `Sources/translate/Domain/Errors.swift`
- `Sources/translate/Domain/ExitCodes.swift`
- `Sources/translate/Execution/TranslationOrchestrator.swift`
- `Sources/translate/Input/OutputPlanner.swift`
- `Sources/translate/Prompt/PromptRenderer.swift`

Validation:
- Add focused tests for each message + exit code combination.

Exit criteria:
- Message and exit-code behavior is deterministic and test-covered.

---

## Phase 3: Provider/runtime robustness (non-DeepL)

Objective:
Finish robust behavior for `openai`, `anthropic`, `ollama`, and `openai-compatible`.

Tasks:
1. Harden provider request/response parsing and error classification.
2. Enforce API key/model/base-url precedence and required checks.
3. Ensure retry policy strictly retries only: `429, 500, 502, 503, 504`.
4. Respect `Retry-After` with:
   - case-insensitive header lookup,
   - delta-seconds format,
   - HTTP-date format.
5. Keep timeout semantics per request attempt.
6. Keep context-window errors non-retryable and surfaced with explicit guidance.

Files:
- `Sources/translate/Providers/ProviderFactory.swift`
- `Sources/translate/Providers/HTTP/HTTPClient.swift`
- `Sources/translate/Providers/HTTP/OpenAICompatibleProvider.swift`
- `Sources/translate/Providers/HTTP/AnthropicProvider.swift`

Validation:
- provider factory tests,
- retry policy tests,
- timeout tests,
- precedence tests.

Exit criteria:
- Non-DeepL HTTP providers are production-stable and fully tested.

---

## Phase 4: Apple provider completion

Objective:
Implement `apple-translate` and `apple-intelligence` with correct startup gating and prompt compatibility behavior.

Tasks:
1. Implement real `apple-translate` translation path.
2. Implement `apple-intelligence` path using `AnyLanguageModel`.
3. Enforce provider-specific inapplicable flags (`--model`, `--api-key`, prompt flags as applicable).
4. Add startup checks for macOS availability with clear errors.
5. Preserve prompt-less provider warning behavior.

Files:
- `Sources/translate/Providers/Apple/AppleTranslateProvider.swift`
- `Sources/translate/Providers/Apple/AppleIntelligenceProvider.swift`
- `Sources/translate/Providers/ProviderFactory.swift`
- `Sources/translate/Execution/TranslationOrchestrator.swift`

Validation:
- unit tests with gating checks,
- runtime smoke tests on supported/unsupported environments.

Exit criteria:
- Apple providers behave correctly with availability and flag semantics.

---

## Phase 5: Streaming, file safety, and concurrency polish

Objective:
Ensure runtime output behavior matches spec under stdout vs file outputs and multi-file workloads.

Tasks:
1. Stream only for stdout output targets.
2. Buffer for file writes to avoid partial writes.
3. Ensure streamed delta output never duplicates characters.
4. Keep bounded concurrency behavior for `--jobs` in multi-file mode.
5. Verify continue-on-error summary remains correct under concurrency.

Files:
- `Sources/translate/Execution/TranslationOrchestrator.swift`
- `Sources/translate/Execution/OutputWriter.swift`

Validation:
- streaming tests,
- multi-file partial-failure tests,
- concurrency correctness tests.

Exit criteria:
- Output behavior is safe, stable, and spec-consistent.

---

## Phase 6: `.xcstrings` workflow integration

Objective:
Implement catalog translation workflow using `StringCatalogKit` and map CLI options correctly.

Tasks:
1. Detect `.xcstrings` input and route into catalog workflow.
2. Build provider bridge into `CatalogTranslationLLM` translator contract.
3. Map `--jobs` to `TranslationOptions(maxConcurrentRequests:)`.
4. Preserve partial-failure reporting semantics for catalog runs.
5. Add catalog fixtures and regression tests.

Files (add/update):
- `Sources/translate/Catalog/CatalogWorkflow.swift`
- `Sources/translate/Catalog/CatalogBridge.swift`
- `Sources/translate/Execution/TranslationOrchestrator.swift`

Validation:
- `CatalogWorkflowTests` with fixture catalogs.

Exit criteria:
- `.xcstrings` translation path works end-to-end and is tested.

---

## Phase 7: Subcommand parity and config UX completion

Objective:
Finish spec-level subcommand behavior details and UX edge cases.

Tasks:
1. `config show/path/get/set/unset/edit` output and error behavior parity.
2. `config edit` fallback chain correctness: `$EDITOR` -> `vi` (Unix/macOS) or `notepad` (Windows).
3. `presets list/show/which` parity:
   - raw placeholders retained in `presets show`,
   - active/default marker behavior.
4. Emit named-endpoint collision warnings at config load time on every invocation.

Files:
- `Sources/translate/CLI/Commands/ConfigCommand.swift`
- `Sources/translate/CLI/Commands/PresetsCommand.swift`
- `Sources/translate/Config/ConfigResolver.swift`
- `Sources/translate/Prompt/PresetResolver.swift`

Validation:
- command-level integration tests and snapshots.

Exit criteria:
- subcommands match the expected spec behavior in normal and edge paths.

---

## Phase 8: Full parity test suite and release gate

Objective:
Build final confidence gate before DeepL unblock.

Tasks:
1. Expand test suite to include:
   - `CLITests`
   - `ConfigTests`
   - `InputResolverTests`
   - `OutputPlannerTests`
   - `PromptTests`
   - `ProviderFactoryTests`
   - `RetryPolicyTests`
   - `StreamingTests`
   - `ConfigEditTests`
   - `HelpSnapshotTests`
   - `CatalogWorkflowTests`
   - `SpecAssertionTests`
2. Add scenario tests from spec Section 12.
3. Update `notes/spec-assertion-checklist.md` to PASS/FAIL per item.
4. Update `notes/spec_parity.md` to mark all non-DeepL items complete.

Validation commands:
1. `swift build`
2. `swift test`
3. `swift run translate --help`
4. `swift run translate config show`
5. `swift run translate presets list`

Exit criteria:
- all non-DeepL parity items are green and documented.

---

## Phase 9 (blocked): DeepL integration when package is ready

Status:
Blocked pending external DeepL package readiness.

Tasks after unblock:
1. Implement `DeepLProvider` behind existing provider contract.
2. Add prompt-less provider semantics and warnings for DeepL.
3. Wire API key precedence (`--api-key` > config > `DEEPL_API_KEY`).
4. Add retry/timeout behavior through shared HTTP client.
5. Add DeepL-specific tests and scenario coverage.
6. Mark Section 7 parity complete in `spec_parity.md`.

Files (add/update):
- `Sources/translate/Providers/DeepL/DeepLProvider.swift`
- `Sources/translate/Providers/ProviderFactory.swift`
- `Tests/translateTests/DeepLProviderTests.swift`

Exit criteria:
- full provider matrix complete, including DeepL.

---

## Recommended execution order for developer

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 6
7. Phase 7
8. Phase 8
9. Phase 9 (only when DeepL package unblocks)

This order minimizes rework: core UX + validation first, then provider/runtime stability, then catalog integration, then full parity gate, then DeepL finalization.
