# translate CLI: Swift Package Exploration and Spec Fit

Date: 2026-02-21

## 1) Setup Status

Initialized executable Swift package with `swift package init --type executable --name translate`, added dependencies from `notes/swift-packages-to-use.md`, and resolved/build-verified them.

Key setup results:
- Package initialized in this repo.
- Dependencies resolved into `.build/checkouts/`.
- Build succeeds with `swift build`.
- Package platform set to `macOS 14` because dependency minimums require it.

Direct dependencies currently in `Package.swift`:
- `apple/swift-argument-parser` `from: 1.7.0`
- `mattt/AnyLanguageModel` `from: 0.7.1`
- local package: `../StringCatalogKit`
- `LebJe/TOMLKit` `from: 0.6.0`

Resolved versions (`Package.resolved`):
- `swift-argument-parser` 1.7.0
- `AnyLanguageModel` 0.7.1
- `TOMLKit` 0.6.0
- plus transitive: `EventSource`, `JSONSchema`, `PartialJSONDecoder`, `swift-collections`, `swift-syntax`

## 2) Package-by-Package Fit to `translate-cli-spec.md`

## `swift-argument-parser`

Best fit for all CLI ergonomics in spec:
- Root command + subcommands (`config`, `presets`) via `CommandConfiguration`.
- Async flows (`AsyncParsableCommand`) for network translation calls.
- Type-safe flags/options/arguments (including repeated positional file args).
- Validation via `validate()` and `ValidationError` for conflict rules in Section 11.
- Explicit exit signaling via `ExitCode` for code mapping (0/1/2/3).

Where it fits:
- Section 2/3/4 (all input/output/provider/prompt/utility flags)
- Section 9 (`config` subcommand)
- Section 10 (`presets` subcommand)
- Section 11 (argument conflict and validation errors)
- Section 16 (help text generation, with custom usage/abstract/discussion)

Implementation notes:
- Represent providers/format as enums conforming to `ExpressibleByArgument`.
- Use `@Argument var inputs: [String]` for `STRING|FILE...` behavior.
- Implement conflict checks in `validate()` to map to exit code `2`.
- For non-TTY confirmation failure, throw `ExitCode(3)` after printing required message.

## `AnyLanguageModel`

Strong fit for LLM-style providers and streaming behavior:
- OpenAI: `OpenAILanguageModel`
- Anthropic: `AnthropicLanguageModel`
- Ollama: `OllamaLanguageModel`
- OpenAI-compatible endpoints: `OpenAILanguageModel(baseURL:..., model:...)`
- Streaming support available through `LanguageModelSession.streamResponse(...)`

Where it fits:
- Section 7.1 and 7.2 for `openai`, `anthropic`, `ollama`, `openai-compatible`
- Section 3.1 streaming behavior for stdout output
- Section 5 prompt templating execution (system prompt + user prompt routed through session)

Important caveats found during source exploration:
- `apple-intelligence` mapping is possible through `SystemLanguageModel`, but in `AnyLanguageModel 0.7.1` it is `@available(macOS 26.0, ...)` in source. Spec says `macOS 15.1` minimum for `apple-intelligence`. This mismatch must be resolved in implementation strategy.
- `AnyLanguageModel` does not include a DeepL client.
- `AnyLanguageModel` does not expose token usage metadata in its public response type, which affects strict implementation of `--verbose` token usage reporting from the spec.

Suggested usage pattern:
- Build a provider adapter layer.
- For prompt-capable providers, create:
  - `LanguageModelSession(model: ..., instructions: systemPrompt)`
  - `respond(to: Prompt(userPrompt))` or `streamResponse(...)` for stdout.

## `StringCatalogKit` (local package)

Excellent fit for `.xcstrings` workflow and the `xcode-strings` preset intent:
- `StringCatalog`: parse and write `.xcstrings`.
- `CatalogTranslation`: segment-level translation engine and file planning/apply APIs.
- `CatalogTranslationLLM`: bridge type (`LLMTranslator`) to plug in custom LLM completion.

Where it fits:
- Section 13.3 `xcode-strings` preset behavior (placeholder safety, UI-focused wording)
- Future `.xcstrings` file handling implementation without rebuilding this logic
- Multi-segment partial-failure reporting model (already present in package types)

Implementation notes:
- You can route the CLI provider abstraction into `LLMTranslator` closure.
- Existing example (`examples/Sources/TranslateCatalogWithOpenAI/main.swift`) already demonstrates this adapter pattern.

## `TOMLKit`

Good fit for config file parsing and serialization:
- Parse TOML config from string/file.
- Structured decoding/encoding for config model.
- Table mutation APIs (`subscript`, `insert`, `remove`).

Where it fits:
- Section 8 config schema and loading
- Section 9 `config show/get/set/unset`

Implementation notes:
- Dot-notation keys (`defaults.provider`) should be handled by our own traversal helper over nested `TOMLTable` values.
- TOMLKit rewrites normalized TOML output; if preserving exact comments/ordering is required later, we may need custom handling.

## 3) Gaps Against Spec (Not Covered by the Current Four Packages)

1. `apple-translate` provider (Section 7.1/7.3/7.5)
- Must be implemented directly with Apple Translation APIs (platform framework), not provided by current dependencies.

2. `deepl` provider
- Must be implemented as direct HTTP client (URLSession + request/response structs + auth + error mapping).

3. Cross-platform glob expansion
- Spec developer notes explicitly call for a glob library.
- Current dependency set does not include a glob package.

4. Token usage in `--verbose`
- Spec asks for token usage output.
- Current `AnyLanguageModel` public API does not surface provider token usage counters.

5. Retry/backoff/timeout policy
- Needs explicit implementation to meet Section 7.6 behavior exactly.

## 4) Do We Need Other Swift Packages?

Short answer: one additional package is recommended; others are optional.

Recommended addition:
- A glob library for deterministic cross-platform wildcard expansion.
- Candidate researched: `davbeck/swift-glob` (native Swift glob matching + directory search API).

Optional additions (only if we want to reduce custom code):
- None strictly required for DeepL; direct URLSession is reasonable.
- None strictly required for Apple Translate; platform framework integration is expected.

Decision summary:
- Mandatory to consider adding: a glob package.
- Not mandatory: additional provider SDK packages (can stay custom and spec-aligned).

## 5) Practical Implementation Sequence (Pre-coding Plan)

1. Lock CLI surface with `swift-argument-parser` command tree and validation matrix.
2. Build config model + TOML IO (`TOMLKit`) + precedence resolver.
3. Implement provider abstraction with `AnyLanguageModel` adapters first (`openai`, `anthropic`, `ollama`, `openai-compatible`).
4. Implement custom `deepl` and `apple-translate` adapters.
5. Add glob package and wire input mode resolver + output mode resolver.
6. Add `.xcstrings` path handling via `StringCatalogKit` and `CatalogTranslationLLM` bridge.
7. Finish retry/timeout, non-TTY confirmations, and exact exit/error contract.
