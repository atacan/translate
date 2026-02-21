# `translate` CLI Implementation Plan (Revision 2)

Date: 2026-02-21  
Scope: planning only, aligned to current repo and dependency APIs.

## Scope/compatibility decisions to lock first

1. DeepL is intentionally postponed by project decision.  
Plan impact: treat DeepL as an explicit spec exception for this milestone; do not claim full Section 7 parity until DeepL phase is executed.

2. Apple Intelligence baseline conflict (spec 15.1 vs current toolchain/dependency 26).  
Plan impact: adopt repo/toolchain reality (`macOS 26`, `AnyLanguageModel.SystemLanguageModel @available(macOS 26.0)`) as implementation baseline for this codebase and document the spec deviation explicitly.

## 1) Proposed architecture (modules/types and responsibilities)

| Module | Key types (planned) | Responsibility | Package usage |
|---|---|---|---|
| CLI Surface | `TranslateCommand`, `ConfigCommand`, `PresetsCommand`, `GlobalOptions` | Parse flags/subcommands and dispatch | `ArgumentParser` |
| Domain | `ProviderID`, `LanguageRef`, `FormatHint`, `InputMode`, `OutputPlan`, `ResolvedOptions`, `AppError`, `ExitCodeMap` | Type-safe core model and error/exit semantics | Foundation |
| Config | `ConfigLocator`, `ConfigStore`, `ConfigResolver`, `ConfigKeyPath` | Resolve config path (`--config` > `TRANSLATE_CONFIG` > default), load/save TOML, dot-key get/set/unset | `TOMLKit` |
| Input/Output Planning | `InputResolver`, `GlobExpander`, `FileInspector`, `OutputPlanner` | Detect input mode, expand globs, validate files, compute output behavior | `Glob`, Foundation |
| Prompting | `BuiltInPresetStore`, `PresetResolver`, `PromptRenderer`, `PromptFileValidator`, `DryRunPrinter` | Template resolution, placeholder substitution, startup prompt-file validation, exact dry-run rendering | Foundation |
| Provider Core | `ProviderRequest`, `ProviderResult`, `ProviderError`, `TranslationProvider`, `ProviderFactory` | Provider-agnostic contract with language direction and deterministic failure metadata | Foundation |
| Provider HTTP Transport | `HTTPClient`, `RetryPolicy`, `OpenAIClient`, `AnthropicClient`, `OllamaClient`, `OpenAICompatibleClient` | Direct HTTP for strict status/header-aware retry and timeout behavior | `URLSession`, `UsefulThings` (`withRetry`) |
| Apple Providers | `AppleIntelligenceProvider`, `AppleTranslateProvider` | macOS-only providers and OS gating | `AnyLanguageModel` (Apple Intelligence), Apple Translation framework |
| Catalog Workflow | `CatalogWorkflow`, `CatalogBridge` | `.xcstrings` routing and translation using actual `StringCatalogKit` API | `StringCatalog`, `CatalogTranslation`, `CatalogTranslationLLM` |
| Diagnostics/Parity | `WarningEmitter`, `VerboseEmitter`, `SpecAssertionMatrix` | Warning policy, verbose info policy, spec-parity checklist assertions | Foundation |

## 2) File/folder plan for `Sources/`

```text
Sources/translate/
  translate.swift
  CLI/
    TranslateCommand.swift
    GlobalOptions.swift
    Commands/
      ConfigCommand.swift
      PresetsCommand.swift
  Domain/
    Models.swift
    Errors.swift
    ExitCodes.swift
    Constants.swift
  Config/
    ConfigLocator.swift
    ConfigStore.swift
    ConfigResolver.swift
    ConfigKeyPath.swift
  Input/
    InputResolver.swift
    GlobExpander.swift
    FileInspector.swift
    OutputPlanner.swift
  Prompt/
    BuiltInPresetStore.swift
    PresetResolver.swift
    PromptRenderer.swift
    PromptFileValidator.swift
    DryRunPrinter.swift
  Providers/
    TranslationProvider.swift
    ProviderFactory.swift
    ProviderRequest.swift
    ProviderResult.swift
    HTTP/
      HTTPClient.swift
      RetryPolicy.swift
      RetryAdapter.swift
      OpenAIClient.swift
      AnthropicClient.swift
      OllamaClient.swift
      OpenAICompatibleClient.swift
    Apple/
      AppleIntelligenceProvider.swift
      AppleTranslateProvider.swift
    DeepL/
      DeepLProvider.swift  # deferred milestone hook
  Catalog/
    CatalogWorkflow.swift
    CatalogBridge.swift
  Execution/
    TranslationOrchestrator.swift
    ConfirmationPrompter.swift
    OutputWriter.swift
    ResponseSanitizer.swift
  Support/
    LanguageNormalizer.swift
    FormatDetector.swift
    TerminalIO.swift

Tests/translateTests/
  CLITests.swift
  ConfigTests.swift
  InputResolverTests.swift
  OutputPlannerTests.swift
  PromptTests.swift
  ProviderFactoryTests.swift
  RetryPolicyTests.swift
  StreamingTests.swift
  ConfigEditTests.swift
  HelpSnapshotTests.swift
  CatalogWorkflowTests.swift
  SpecAssertionTests.swift
```

## 3) Ordered implementation phases

1. Phase 0: scope and platform compatibility lock  
2. Phase 1: CLI/domain skeleton  
3. Phase 2: config system and precedence  
4. Phase 3: input/output planning and file validation  
5. Phase 4: prompt engine and dry-run parity  
6. Phase 5: provider contract + transport layer + provider factory  
7. Phase 6: runtime execution (streaming/retry/confirmations/sanitization)  
8. Phase 7: `config` and `presets` subcommands  
9. Phase 8: `.xcstrings` workflow integration  
10. Phase 9: spec-assertion hardening and release gate  
11. DeepL later: deferred follow-up milestone

## 4) Phase details

### Phase 0
**Objective**  
Lock explicit scope exceptions and compatibility assumptions before coding.

**Concrete tasks**
- Record “DeepL deferred” as a tracked exception.
- Record Apple Intelligence macOS 26 baseline decision.
- Add a `spec_parity.md` tracker with section status: `done`, `deferred`, `exception`.

**Small Swift snippets**
```swift
enum MilestoneScope {
    static let deepLEnabled = false
}
```

```swift
enum PlatformBaseline {
    static let minimumMacOSMajor = 26
}
```

**Validation/tests to run**
- Manual review: scope tracker approved.

**Exit criteria**
- No ambiguity remains on DeepL and Apple-version expectations.

### Phase 1
**Objective**  
Create compileable command surface and shared core types.

**Concrete tasks**
- Replace hello-world with `AsyncParsableCommand` root.
- Add typed options/enums and exit-code mapping.
- Scaffold command routing and tests.

**Small Swift snippets**
```swift
@main
struct TranslateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "translate",
        subcommands: [ConfigCommand.self, PresetsCommand.self]
    )
}
```

```swift
enum ExitCodeMap: Int32 {
    case success = 0, runtimeError = 1, invalidArguments = 2, aborted = 3
}
```

**Validation/tests to run**
- `swift build`
- `swift run translate --help`
- `swift test --filter CLITests`

**Exit criteria**
- CLI tree and basic parsing are stable.

### Phase 2
**Objective**  
Implement config reading/writing and full precedence, including env vars and API-key resolution.

**Concrete tasks**
- Implement config path resolver: `--config` > `TRANSLATE_CONFIG` > default path.
- Expand `~` and relative paths to absolute filesystem paths before read/write and for `config path` output.
- Implement hybrid TOML strategy:
  - typed structs for stable fields
  - `TOMLTable` traversal for dynamic/hyphenated keys like `providers.openai-compatible.<name>`
- Implement `config get/set/unset` dot-notation on `TOMLTable`.
- Parse and validate runtime network config from TOML:
  - `network.timeout_seconds`
  - `network.retries`
  - `network.retry_base_delay_seconds`
- Implement option precedence:
  - CLI > preset > defaults > built-in.
- Implement API-key precedence:
  - CLI `--api-key` > config `api_key` > env var.
- Ensure config file creation with `0600`.

**Small Swift snippets**
```swift
func resolvedConfigPath(cli: String?, env: [String: String], home: URL) -> URL {
    let raw = cli ?? env["TRANSLATE_CONFIG"] ?? "~/.config/translate/config.toml"
    return expandToAbsoluteURL(raw, homeDirectory: home)
}
```

```swift
enum ProvidersCodingKeys: String, CodingKey {
    case openai, anthropic, ollama, deepl
    case openAICompatible = "openai-compatible"
}
```

```swift
struct NetworkRuntimeConfig {
    let timeoutSeconds: Int
    let retries: Int
    let retryBaseDelaySeconds: Int
}
```

**Validation/tests to run**
- `swift test --filter ConfigTests`
- Round-trip tests for config with named `openai-compatible` endpoints.
- Permission test on newly created config file.
- Tests asserting `config path` prints expanded absolute path.
- Tests asserting `[network]` values are loaded and surfaced into resolved runtime settings.

**Exit criteria**
- Config/env precedence is deterministic and covered by tests.

### Phase 3
**Objective**  
Deliver spec-accurate input mode and output mode planning with correct exit-code classes.

**Concrete tasks**
- Implement inline/file/stdin detection and ambiguity resolution.
- Implement cross-platform glob expansion with `swift-glob`.
- Implement file checks: binary/invalid UTF-8/empty warnings.
- Implement output plan including glob single-match file-output rule.
- Map glob zero-match as runtime failure (exit code `1`) instead of argument conflict (`2`).

**Small Swift snippets**
```swift
func looksLikeGlob(_ s: String) -> Bool {
    s.contains("*") || s.contains("?") || s.contains("[")
}
```

```swift
let pattern = try Pattern(rawPattern)
for try await url in search(directory: cwd, include: [pattern]) {
    files.append(url)
}
```

**Validation/tests to run**
- `swift test --filter InputResolverTests`
- `swift test --filter OutputPlannerTests`
- Manual:
  - `swift run translate "*.md" --to fr --dry-run`
  - `swift run translate missing*.md --to fr`

**Exit criteria**
- Input/output planning behavior and exit-code mapping match spec intent.

### Phase 4
**Objective**  
Implement prompt templating system and strict dry-run format parity.

**Concrete tasks**
- Add built-in presets and shadowing rules.
- Implement placeholders and `from=auto -> "the source language"`.
- Validate `system_prompt_file` and `user_prompt_file` at startup.
- Implement warning for custom prompt without `{from}`/`{to}`.
- Implement warning for `--no-lang` when no custom prompt is active.
- Implement `--base-url` auto-provider info message.
- Implement exact dry-run sections and “first 500 chars” truncation.

**Small Swift snippets**
```swift
let preview = input.count > 500 ? String(input.prefix(500)) + "..." : input
```

```swift
if options.noLang && !resolvedPrompt.isCustom {
    warnings.warn("--no-lang has no effect when using default prompts.")
}
```

**Validation/tests to run**
- `swift test --filter PromptTests`
- Golden snapshot tests for dry-run output and warnings.

**Exit criteria**
- Prompt/warning/dry-run behaviors match Sections 5, 6, 11, 13.

### Phase 5
**Objective**  
Implement provider abstraction and provider factory with metadata-aware contract.

**Concrete tasks**
- Define provider protocol with language direction and metadata output.
- Implement HTTP provider clients (OpenAI, Anthropic, Ollama, openai-compatible) via direct `URLSession`.
- Implement Apple Intelligence provider using `AnyLanguageModel.SystemLanguageModel`.
- Implement Apple Translate provider as prompt-less path.
- Implement provider selection and `--base-url` rules.
- Define typed `ProviderError` carrying status/headers/body and classify retryability deterministically.

**Small Swift snippets**
```swift
struct ProviderRequest: Sendable {
    let from: LanguageRef
    let to: LanguageRef
    let systemPrompt: String?
    let userPrompt: String?
    let text: String
}
```

```swift
struct ProviderResult: Sendable {
    let text: String
    let usage: UsageInfo?
    let statusCode: Int?
    let headers: [String: String]
}
```

```swift
enum ProviderError: Error, Sendable {
    case http(statusCode: Int, headers: [String: String], body: String)
    case timeout(seconds: Int)
    case invalidResponse(String)
    case transport(String)
}
```

```swift
protocol TranslationProvider: Sendable {
    var id: ProviderID { get }
    func translate(_ request: ProviderRequest) async throws(ProviderError) -> ProviderResult
}
```

**Validation/tests to run**
- `swift test --filter ProviderFactoryTests`
- Contract tests for provider selection and incompatible flag errors.

**Exit criteria**
- Provider interface supports prompt-capable and prompt-less providers cleanly.

### Phase 6
**Objective**  
Implement runtime orchestration: retries, timeout, streaming, sanitization, and confirmations.

**Concrete tasks**
- Build orchestration for single/multi-file runs and summary reporting.
- Implement retry policy in `HTTPClient` via `UsefulThings.withRetry` wrapper.
- Unwrap `RetryError<ProviderError>` from `withRetry` and remap to `lastError` so spec error text and exit semantics are preserved.
- Wire runtime retry/timeout directly from resolved network config (`timeout_seconds`, `retries`, `retry_base_delay_seconds`).
- Respect `Retry-After` override using case-insensitive header lookup and both legal formats (`delta-seconds`, HTTP-date).
- Respect context-window non-retry behavior.
- Add stdout streaming with cumulative-snapshot delta handling.
- Add buffered writes for file outputs.
- Implement fence stripping and non-TTY confirmation abort semantics.
- Keep request timeout per attempt (outside the overall retry loop), matching spec wording.

**Small Swift snippets**
```swift
var emitted = 0
for try await snap in stream {
    let full = snap.content.description
    let delta = String(full.dropFirst(emitted))
    emitted = full.count
    stdout.write(delta)
}
```

```swift
do {
    return try await withRetry(configuration: retryConfig, predicate: retryPredicate) {
        try await singleAttemptRequest()
    }
} catch let e as RetryError<ProviderError> {
    throw e.lastError
}
```

```swift
if let retryAfter = header(named: "retry-after", in: response.headers) {
    delay = parseRetryAfterDeltaSecondsOrHTTPDate(retryAfter, now: clock.now)
}
```

```swift
let retryConfig = RetryConfiguration(
    maxAttempts: network.retries + 1,
    initialDelay: .seconds(network.retryBaseDelaySeconds),
    maxDelay: .seconds(30),
    backoffMultiplier: 2.0,
    jitterFactor: 0.2
)
let perRequestTimeout = Duration.seconds(network.timeoutSeconds)
```

**Validation/tests to run**
- `swift test --filter RetryPolicyTests`
- `swift test --filter StreamingTests`
- CI-style non-TTY integration tests for confirmation flow.
- Retry tests proving only 429/500/502/503/504 are retried.
- Retry tests proving `Retry-After` header lookup is case-insensitive.
- Retry tests proving both `Retry-After` formats are supported: `delta-seconds` and HTTP-date.
- Retry tests proving `Retry-After` overrides computed delay.
- Retry tests proving `RetryError<ProviderError>` is remapped to `lastError`.
- Timeout tests proving timeout is per request attempt, not whole sequence.
- Tests proving config overrides for `[network]` are applied to retry/timeout behavior.

**Exit criteria**
- No duplicate streamed output; retry policy follows spec.

### Phase 7
**Objective**  
Complete `config` and `presets` subcommands.

**Concrete tasks**
- Implement `config show/path/get/set/unset/edit`.
- Implement `presets list/show/which`.
- Ensure `presets show` keeps placeholders intact.
- Ensure named-endpoint collision warning is emitted at config load time.
- Implement `config edit` fallback chain and tests: `$EDITOR` -> `vi` (Unix/macOS) / `notepad` (Windows).

**Small Swift snippets**
```swift
struct PresetsShow: ParsableCommand {
    @Argument var name: String
    mutating func run() throws { /* print raw templates */ }
}
```

```swift
if builtInProviderNames.contains(endpointName) {
    warnings.warn("Named endpoint '\(endpointName)' ... will never be used.")
}
```

**Validation/tests to run**
- `swift test --filter CLITests`
- `swift test --filter ConfigEditTests`
- Snapshot tests for `presets list/show/which`.

**Exit criteria**
- Subcommands match spec behavior and output format.

### Phase 8
**Objective**  
Integrate `.xcstrings` translation with correct `StringCatalogKit` APIs and `--jobs` mapping.

**Concrete tasks**
- Route `.xcstrings` input into catalog workflow.
- Bridge provider abstraction into `LLMTranslator`.
- Construct `CatalogTranslationEngine(translator:options:)`.
- Map CLI `--jobs` to `TranslationOptions(maxConcurrentRequests:)`.

**Small Swift snippets**
```swift
let translator = LLMTranslator { request, systemPrompt, userPrompt in
    let providerReq = ProviderRequest(
        from: .languageCode(request.sourceLanguage.rawValue),
        to: .languageCode(request.targetLanguage.rawValue),
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        text: request.text
    )
    return try await provider.translate(providerReq).text
}
```

```swift
let options = TranslationOptions(maxConcurrentRequests: resolved.jobs)
let engine = CatalogTranslationEngine(translator: translator, options: options)
let result = try await engine.translateCatalog(catalog, to: targetLanguage)
```

**Validation/tests to run**
- `swift test --filter CatalogWorkflowTests`
- Fixture tests for `.xcstrings` translation and partial failures.

**Exit criteria**
- `.xcstrings` flow compiles and behaves as planned using real package APIs.

### Phase 9
**Objective**  
Add incremental spec assertion gate and release-readiness checks.

**Concrete tasks**
- Create `notes/spec-assertion-checklist.md` (error text, warning text, exit codes, dry-run layout).
- Add `SpecAssertionTests` mapped to each checklist entry.
- Run behavior scenarios from spec Section 12.
- Add full `--help` snapshot parity tests (root + `config` + `presets` help output).
- Add explicit warning assertions for:
  - `--jobs` used with inline text/stdin (`--jobs has no effect for non-file input`)
  - `--suffix` used with single explicit file to stdout (`--suffix has no effect when outputting to stdout`)

**Small Swift snippets**
```swift
XCTAssertEqual(run("translate --verbose --quiet").exitCode, 2)
XCTAssertContains(run(...).stderr, "--verbose and --quiet cannot be used together.")
```

```swift
let checklistStatus = ["§11.1-verbose-quiet-conflict": "PASS"]
```

**Validation/tests to run**
- `swift test`
- `swift test --filter HelpSnapshotTests`
- Manual smoke for help/version/subcommands.

**Exit criteria**
- Parity matrix is explicit and green for in-scope items.

## 5) Risk/ambiguity list from spec + recommended decisions

1. DeepL deferred vs spec support list  
Recommendation: keep explicit exception entry and do not claim full provider parity in this milestone.

2. Apple Intelligence minimum version mismatch  
Recommendation: document codebase baseline as macOS 26 and track as spec deviation.

3. Retry/timeout observability with AnyLanguageModel for HTTP providers  
Recommendation: use direct HTTP clients for those providers; keep AnyLanguageModel for Apple Intelligence only.

4. Deterministic retry decisions require typed transport errors  
Recommendation: enforce `ProviderError.http(statusCode:headers:body:)` so retry policy is purely data-driven.

5. Streaming snapshot semantics (cumulative content)  
Recommendation: always emit delta from last character count when writing to stdout.

6. Glob zero-match exit code classification  
Recommendation: treat as runtime/input failure (`1`), not argument conflict (`2`).

7. Dynamic TOML key structure (`openai-compatible` + named children)  
Recommendation: hybrid typed model + `TOMLTable` traversal for dynamic branches.

8. Language normalization coverage (name/ISO/BCP47)  
Recommendation: implement dedicated normalizer using Foundation locale APIs plus a curated alias table; do not rely on `StringCatalogKit` language enum for CLI parsing.

9. Token usage in verbose output may be unavailable per provider  
Recommendation: emit usage when available; otherwise print `token usage: unavailable`.

## 6) “DeepL later” placeholder plan (where it will plug in)

DeepL remains out of this milestone by explicit scope decision. The integration point is preserved so later implementation is additive.

- Plug point: `Sources/translate/Providers/DeepL/DeepLProvider.swift`, `ProviderFactory`.
- Contract: implement `TranslationProvider.translate(_:) async throws(ProviderError) -> ProviderResult`.
- Behavior requirements when enabled:
  - Prompt-less provider warnings (`--system-prompt`, `--user-prompt`, `--context`, `--format`, prompt portion of `--preset` ignored).
  - `--to` concrete resolution required.
  - API key precedence: CLI > config > `DEEPL_API_KEY`.
  - Retry/timeout through shared `HTTPClient` + `RetryPolicy`.
- Validation set for follow-up milestone:
  - unit tests for request/response mapping,
  - retry/status code behavior,
  - CLI acceptance scenarios from Section 12.

## 7) Final checklist mapping spec sections -> planned components

| Spec section | Planned component(s) | Status in this milestone |
|---|---|---|
| 1. Overview | `CLI/TranslateCommand.swift`, `Execution/TranslationOrchestrator.swift` | In scope |
| 2. Input Modes | `Input/InputResolver.swift`, `Input/GlobExpander.swift`, `Input/FileInspector.swift` | In scope |
| 3. Output Modes | `Input/OutputPlanner.swift`, `Execution/OutputWriter.swift` | In scope |
| 4. Full Flag Reference | `CLI/GlobalOptions.swift` | In scope |
| 5. Prompt Templating | `Prompt/PromptRenderer.swift`, `Prompt/DryRunPrinter.swift` | In scope |
| 6. Presets | `Prompt/BuiltInPresetStore.swift`, `Prompt/PresetResolver.swift` | In scope |
| 7. Providers | `Providers/*`, `Providers/HTTP/*`, `Providers/Apple/*` | DeepL deferred exception |
| 8. Configuration File | `Config/ConfigStore.swift`, `Config/ConfigResolver.swift` | In scope |
| 9. `config` subcommand | `CLI/Commands/ConfigCommand.swift` | In scope |
| 10. `presets` subcommand | `CLI/Commands/PresetsCommand.swift` | In scope |
| 11. Validation and errors | `Domain/Errors.swift`, `Execution/TranslationOrchestrator.swift`, `SpecAssertionTests.swift` | In scope |
| 12. Scenario behavior | `Tests/translateTests/CLITests.swift` | In scope |
| 13. Default prompts | `Prompt/BuiltInPresetStore.swift` | In scope |
| 14. Environment variables | `Config/ConfigLocator.swift`, provider factories | In scope |
| 15. Exit codes | `Domain/ExitCodes.swift` | In scope |
| 16. Help text | `CLI/TranslateCommand.swift` help definitions | In scope |
| 17. Developer notes | `Execution/RetryPolicy.swift`, `Execution/ResponseSanitizer.swift`, `Input/GlobExpander.swift` | In scope |
