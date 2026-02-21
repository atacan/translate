# `translate` CLI Implementation Plan (No Full Implementation)

Date: 2026-02-21  
Scope: planning only, based on `/Users/atacan/Developer/Repositories/translate/translate-cli-spec.md` and current repo state.

## 1) Proposed architecture (modules/types and responsibilities)

| Module | Key Types (planned) | Responsibility | Package usage |
|---|---|---|---|
| CLI Surface | `TranslateCommand`, `ConfigCommand`, `PresetsCommand`, `GlobalOptions` | Parse args/flags, wire subcommands, run top-level validation and dispatch | `ArgumentParser` |
| Domain Models | `ProviderID`, `LanguageRef`, `FormatHint`, `InputMode`, `OutputPlan`, `ResolvedOptions`, `AppError` | Central strongly typed model layer for behavior from spec sections 2–15 | Foundation only |
| Config & Presets | `AppConfig`, `DefaultsConfig`, `ProviderConfig`, `PresetConfig`, `ConfigStore`, `ConfigKeyPath` | Load/merge config TOML, write config updates, resolve presets and precedence | `TOMLKit` |
| Input Discovery | `InputResolver`, `GlobExpander`, `FileInspector` | Resolve inline/file/stdin mode, expand globs cross-platform, binary/UTF-8/empty checks | `Glob`, Foundation |
| Prompt Engine | `PromptTemplateResolver`, `PlaceholderContext`, `PromptFileLoader`, `PromptWarningEngine` | Resolve preset + custom prompt templates + placeholders + dry-run output | Foundation |
| Provider Abstraction | `TranslationProvider` protocol, `ProviderFactory`, adapters (`OpenAIProvider`, `AnthropicProvider`, `OllamaProvider`, `OpenAICompatibleProvider`, `AppleIntelligenceProvider`, `AppleTranslateProvider`) | Provider-agnostic translation execution with capability metadata | `AnyLanguageModel` + Foundation + Apple frameworks |
| Catalog Translation | `CatalogWorkflow`, `CatalogProviderBridge` | `.xcstrings` flow via existing engine and LLM bridge | `StringCatalog`, `CatalogTranslation`, `CatalogTranslationLLM` |
| Execution Pipeline | `TranslationOrchestrator`, `RetryPolicy`, `ConfirmationPrompter`, `OutputWriter`, `RunSummary` | Streaming vs buffered behavior, retries/timeouts, confirmations, multi-file parallel execution, exit code mapping | Foundation concurrency |
| Diagnostics | `Logger`, `VerboseReport`, `WarningSink` | stderr warnings/info, `--quiet`/`--verbose` behavior, failure summaries | Foundation only |

## 2) File/folder plan for `Sources/`

```text
Sources/translate/
  translate.swift                      # @main entry only
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
    AppConfig.swift
    ConfigStore.swift
    ConfigMerge.swift
    ConfigKeyPath.swift
  Input/
    InputResolver.swift
    GlobExpander.swift
    FileInspector.swift
  Prompt/
    PromptTemplates.swift
    PromptRenderer.swift
    PromptFileLoader.swift
  Providers/
    TranslationProvider.swift
    ProviderFactory.swift
    AnyLanguageModel/
      OpenAIProvider.swift
      AnthropicProvider.swift
      OllamaProvider.swift
      OpenAICompatibleProvider.swift
      AppleIntelligenceProvider.swift
    AppleTranslate/
      AppleTranslateProvider.swift
    DeepL/
      DeepLProvider.swift              # phase placeholder only initially
  Catalog/
    CatalogWorkflow.swift
    CatalogProviderBridge.swift
  Execution/
    TranslationOrchestrator.swift
    RetryPolicy.swift
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
  PromptTests.swift
  InputResolverTests.swift
  OutputPlanTests.swift
  ProviderResolutionTests.swift
  ResponseSanitizerTests.swift
  CatalogWorkflowTests.swift
```

## 3) Ordered implementation phases

1. Phase 1: CLI skeleton + core domain contracts  
2. Phase 2: Config/preset data model + precedence resolver  
3. Phase 3: Input mode detection + glob/file validation + output planning  
4. Phase 4: Prompt templating + custom prompt file loading + dry-run  
5. Phase 5: Provider factory + AnyLanguageModel-backed adapters + Apple gating  
6. Phase 6: Execution orchestration (streaming/buffering, retries, sanitization, confirmations)  
7. Phase 7: `config` and `presets` subcommands  
8. Phase 8: `.xcstrings` workflow wiring through `StringCatalogKit`  
9. Phase 9: Hardening pass (validation matrix, exit codes, integration tests, help text parity)

## 4) Phase details

### Phase 1
**Objective**  
Establish a compileable CLI shape and shared domain model boundaries before behavior implementation.

**Concrete tasks**
- Replace hello-world entrypoint with `AsyncParsableCommand` root + subcommands.
- Add typed enums for provider/format/language input forms.
- Define shared error + exit code mapping contract.
- Add initial test target scaffolding.

**Small Swift snippets**
```swift
@main
struct TranslateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "translate",
        subcommands: [ConfigCommand.self, PresetsCommand.self]
    )

    @Argument var inputs: [String] = []
    @Option(name: .shortAndLong) var to: String?

    mutating func run() async throws {
        // dispatch to orchestrator in later phases
    }
}
```

```swift
enum ExitCodeMap: Int32 {
    case success = 0
    case runtimeError = 1
    case invalidArguments = 2
    case aborted = 3
}
```

**Validation/tests to run**
- `swift build`
- `swift run translate --help`
- `swift test` (empty scaffolding should pass)

**Exit criteria**
- CLI starts with expected command tree.
- Build/test pipeline is green.
- No business logic mixed into entrypoint.

### Phase 2
**Objective**  
Implement config load/write + effective option resolution: CLI > preset > config defaults > built-ins.

**Concrete tasks**
- Create `AppConfig` Codable model aligned with Section 8 schema.
- Implement `ConfigStore.load/save` using `TOMLDecoder`/`TOMLEncoder`.
- Implement dot-path key resolver for `config get/set/unset`.
- Add merge resolver producing `ResolvedOptions`.

**Small Swift snippets**
```swift
struct AppConfig: Codable {
    var defaults: DefaultsConfig?
    var network: NetworkConfig?
    var providers: ProvidersConfig?
    var presets: [String: PresetConfig]?
}
```

```swift
struct ConfigStore {
    func load(from path: URL) throws -> AppConfig {
        let text = try String(contentsOf: path, encoding: .utf8)
        return try TOMLDecoder().decode(AppConfig.self, from: text)
    }
}
```

**Validation/tests to run**
- `swift test --filter ConfigTests`
- Round-trip test: decode -> encode -> decode for sample TOML.
- File mode test for `0600` permission creation on macOS.

**Exit criteria**
- Effective config resolution is deterministic and unit-tested.
- Dot-path read/write/unset semantics are stable.

### Phase 3
**Objective**  
Implement robust input classification and output target planning before network/provider calls.

**Concrete tasks**
- Build input mode classifier: inline text vs file(s) vs stdin.
- Add wildcard detection and explicit glob expansion with `swift-glob`.
- Add file checks: exists, binary, UTF-8, empty warning.
- Build output plan (`stdout`, single `--output`, in-place, or generated multi-file names).

**Small Swift snippets**
```swift
func looksLikeGlob(_ value: String) -> Bool {
    value.contains("*") || value.contains("?") || value.contains("[")
}
```

```swift
let pattern = try Pattern(rawPattern)
for try await match in search(directory: cwdURL, include: [pattern]) {
    resolvedFiles.append(match)
}
```

**Validation/tests to run**
- `swift test --filter InputResolverTests`
- `swift test --filter OutputPlanTests`
- Manual checks:
  - `swift run translate "*.md" --to fr --dry-run`
  - `swift run translate --text document.md --to en --dry-run`

**Exit criteria**
- Spec-compliant input mode and output mode decisions are covered by tests.
- Glob zero-match and conflict errors return exit code `2` with exact wording.

### Phase 4
**Objective**  
Implement presets + prompt templating engine and `--dry-run` output.

**Concrete tasks**
- Add built-in prompt table for `general/markdown/xcode-strings/legal/ui`.
- Implement preset shadowing and resolution order.
- Implement placeholders (`{from}`, `{to}`, `{text}`, `{context}`, `{context_block}`, `{filename}`, `{format}`).
- Implement `@file` prompt loading and missing file error.
- Implement custom-prompt language placeholder warning and `--no-lang` suppression.

**Small Swift snippets**
```swift
struct PlaceholderContext {
    let fromDisplay: String
    let toDisplay: String
    let text: String
    let context: String
    let filename: String
    let format: String
}
```

```swift
func render(_ template: String, with c: PlaceholderContext) -> String {
    template
        .replacingOccurrences(of: "{from}", with: c.fromDisplay)
        .replacingOccurrences(of: "{to}", with: c.toDisplay)
        .replacingOccurrences(of: "{text}", with: c.text)
}
```

**Validation/tests to run**
- `swift test --filter PromptTests`
- Golden tests for dry-run output formatting.
- Warning suppression tests with `--quiet` and `--no-lang`.

**Exit criteria**
- Prompt resolution behavior matches Section 5 + Section 13.
- Dry-run never touches provider code.

### Phase 5
**Objective**  
Implement provider resolution/factory and LLM provider adapters (DeepL intentionally deferred).

**Concrete tasks**
- Define `TranslationProvider` protocol with capability flags (`supportsPrompts`, `supportsModel`, `supportsAPIKey`).
- Implement adapters:
  - OpenAI / Anthropic / Ollama / anonymous openai-compatible / named openai-compatible via `AnyLanguageModel`.
  - Apple Intelligence via `SystemLanguageModel` (macOS 26 target compatible).
  - Apple Translate adapter as prompt-less provider (native framework wrapper).
- Implement provider-selection rules and unknown-provider handling.
- Implement provider-flag compatibility warnings and errors from Section 11.

**Small Swift snippets**
```swift
protocol TranslationProvider: Sendable {
    var id: ProviderID { get }
    var supportsPrompts: Bool { get }
    func translate(systemPrompt: String?, userPrompt: String) async throws -> String
}
```

```swift
let model = OpenAILanguageModel(
    baseURL: baseURL,
    apiKey: apiKey,
    model: modelID
)
let session = LanguageModelSession(model: model, instructions: systemPrompt ?? "")
let response = try await session.respond(to: userPrompt)
```

**Validation/tests to run**
- `swift test --filter ProviderResolutionTests`
- Manual smoke with `--dry-run` and mocked/no-network provider tests.
- OS/provider gating tests for Apple-only providers.

**Exit criteria**
- Provider factory resolves all supported current providers correctly.
- Prompt-less provider ignore warnings and required-flag checks are enforced.

### Phase 6
**Objective**  
Build execution runtime: streaming rules, retry/timeout, response sanitization, confirmations, and multi-file summary behavior.

**Concrete tasks**
- Add orchestration pipeline for single and multi-file runs.
- Implement streaming only for stdout-compatible modes; buffer otherwise.
- Implement retry policy (429/500/502/503/504), exponential backoff, jitter, retry-after.
- Implement timeout handling and context-window error short-circuit (no retry).
- Implement outer code-fence stripping logic.
- Implement interactive confirmation + non-TTY abort behavior (exit code `3`).

**Small Swift snippets**
```swift
func stripOuterFence(_ text: String) -> String {
    // detect full-response fenced wrapper and strip only outermost fence
    return text
}
```

```swift
for try await snapshot in session.streamResponse(to: prompt) {
    FileHandle.standardOutput.write(Data(snapshot.content.description.utf8))
}
```

**Validation/tests to run**
- `swift test --filter ResponseSanitizerTests`
- Integration tests with mocked HTTP provider for retry/timeout.
- Manual non-TTY checks in CI-style shell for confirmation behavior.

**Exit criteria**
- Multi-file partial failures continue and summarize correctly.
- Exit code semantics (0/1/2/3) match spec matrix.

### Phase 7
**Objective**  
Implement `config` and `presets` subcommands end-to-end.

**Concrete tasks**
- `config show/path/get/set/unset/edit` behaviors.
- `presets list/show/which` behaviors with built-in + user-defined sources.
- Add `config edit` editor fallback logic (`$EDITOR` -> `vi`).
- Ensure `presets show` prints raw templates (placeholders intact).

**Small Swift snippets**
```swift
struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [
        ConfigShow.self, ConfigPath.self, ConfigSet.self, ConfigGet.self, ConfigUnset.self, ConfigEdit.self
    ])
}
```

```swift
struct PresetsShow: ParsableCommand {
    @Argument var name: String
    mutating func run() throws {
        // print raw system/user templates with placeholders unchanged
    }
}
```

**Validation/tests to run**
- `swift test --filter CLITests`
- Snapshot tests for `presets list` output grouping/markers.
- Manual `config set/get/unset` round-trip.

**Exit criteria**
- Both subcommands are spec-complete and documented in help output.

### Phase 8
**Objective**  
Wire `.xcstrings` translation flow through `StringCatalogKit` and provider bridge.

**Concrete tasks**
- Detect `.xcstrings` inputs and route to catalog workflow.
- Build bridge from provider abstraction to `CatalogTranslationLLM.LLMTranslator`.
- Ensure placeholder preservation behavior is tested for catalog strings.
- Keep this path provider-agnostic for supported prompt-capable providers.

**Small Swift snippets**
```swift
let llmBridge = LLMTranslator { request, systemPrompt, userPrompt in
    try await provider.translate(systemPrompt: systemPrompt, userPrompt: userPrompt)
}
```

```swift
let engine = CatalogTranslationEngine(textTranslator: llmBridge)
let result = try await engine.translate(catalog, to: targetLanguageCode)
```

**Validation/tests to run**
- `swift test --filter CatalogWorkflowTests`
- Fixture tests for `.xcstrings` read -> translate -> write cycle.

**Exit criteria**
- `.xcstrings` path is deterministic and does not regress normal file/text path.

### Phase 9
**Objective**  
Finalize spec parity and quality hardening before release.

**Concrete tasks**
- Audit all Section 11 hard errors/warnings for exact message text.
- Verify help output parity with Section 16.
- Add end-to-end scenario tests from Section 12 table.
- Ensure collision warning for named endpoint vs built-in provider emits at config load time.

**Small Swift snippets**
```swift
if options.verbose && options.quiet {
    throw CLIError.invalidArguments("--verbose and --quiet cannot be used together.")
}
```

```swift
let code: ExitCodeMap = failures.isEmpty ? .success : .runtimeError
throw ExitCode(rawValue: code.rawValue)
```

**Validation/tests to run**
- `swift test`
- `swift run translate --help`
- Scenario script covering representative commands in Section 12.

**Exit criteria**
- Traceability matrix (spec -> code/tests) is complete.
- No known gaps except explicitly postponed DeepL implementation.

## 5) Risk/ambiguity list from spec + recommended decisions

1. Apple Intelligence version mismatch in ecosystem docs  
Recommendation: treat project target (`macOS 26`) as source of truth for this repo; gate feature at compile/runtime accordingly.

2. `--to` requirement for prompt-less providers vs built-in default `to=en`  
Recommendation: interpret as “must resolve to a concrete value after precedence resolution”; if resolved value exists, proceed without extra error.

3. Token usage in `--verbose` for `AnyLanguageModel` adapters  
Recommendation: include token counts only when accessible; otherwise print `token usage: unavailable` instead of fabricating data.

4. Glob single-match “always file output mode” vs shell pre-expansion  
Recommendation: enforce this rule only when raw argument still contains wildcard characters; document shell-expanded edge case.

5. `TOMLKit` rewrite behavior can reorder formatting/comments  
Recommendation: accept normalized TOML output for v1; preserve correctness over formatting fidelity.

6. Apple Translate markdown preservation limitations  
Recommendation: add explicit user-facing note in help/docs when `apple-translate` is selected.

7. Config unset semantics with nested dot paths  
Recommendation: implement explicit parent-table traversal + key removal; no-op with clear message when key absent.

8. `--jobs` on single/inline/stdin modes  
Recommendation: warn and ignore exactly as spec; keep default orchestration path single-threaded for non-file flows.

## 6) “DeepL later” placeholder plan (where it will plug in)

- Keep `Providers/DeepL/DeepLProvider.swift` as a stub type conforming to `TranslationProvider`.
- Register `.deepl` in `ProviderID` and `ProviderFactory` now, but return a clear “not implemented in this milestone” runtime error until enabled.
- Reuse existing provider capability flow (prompt-less, requires `to`, ignores prompt flags with warnings).
- Planned implementation when unblocked:
  - HTTP client via `URLSession` in `DeepLProvider`.
  - Config/env key resolution: CLI `--api-key` > config `[providers.deepl].api_key` > `DEEPL_API_KEY`.
  - Retry/timeout uses shared `RetryPolicy`.
  - Add contract tests with `URLProtocol` stubs.

## 7) Final checklist mapping spec sections -> planned components

| Spec section | Planned component(s) |
|---|---|
| 1. Overview | `CLI/TranslateCommand.swift`, `Execution/TranslationOrchestrator.swift` |
| 2. Input Modes | `Input/InputResolver.swift`, `Input/GlobExpander.swift`, `Input/FileInspector.swift` |
| 3. Output Modes | `Execution/OutputWriter.swift`, `Domain/Models.swift` (`OutputPlan`) |
| 4. Full Flag Reference | `CLI/GlobalOptions.swift`, `CLI/TranslateCommand.swift` |
| 5. Prompt Templating | `Prompt/PromptRenderer.swift`, `Prompt/PromptFileLoader.swift` |
| 6. Presets | `Config/ConfigMerge.swift`, `Prompt/PromptTemplates.swift` |
| 7. Providers | `Providers/ProviderFactory.swift`, provider adapter files |
| 8. Configuration File | `Config/AppConfig.swift`, `Config/ConfigStore.swift` |
| 9. `config` subcommand | `CLI/Commands/ConfigCommand.swift`, `Config/ConfigKeyPath.swift` |
| 10. `presets` subcommand | `CLI/Commands/PresetsCommand.swift` |
| 11. Validation & errors | `Domain/Errors.swift`, `CLI/GlobalOptions.swift`, `Execution/TranslationOrchestrator.swift` |
| 12. Scenario behavior | `Tests/translateTests/CLITests.swift` scenario suite |
| 13. Default prompts | `Prompt/PromptTemplates.swift` |
| 14. Environment vars | `Config/ConfigStore.swift`, provider adapters |
| 15. Exit codes | `Domain/ExitCodes.swift`, command top-level error mapper |
| 16. Help text | `CLI/TranslateCommand.swift` + option help text |
| 17. Developer notes | `Execution/RetryPolicy.swift`, `Execution/ResponseSanitizer.swift`, `Input/GlobExpander.swift` |

