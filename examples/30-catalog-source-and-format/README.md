# Keep catalog routing and source authoritative

Catalog sourceLanguage en overrides conflicting CLI --from de with a warning. Target equal to source yields no requests in normal mode; forcing that target is rejected. --format markdown changes {format} in the chosen template but .xcstrings remains the catalog route, with English source and catalog format validation.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/30-catalog-source-and-format
```

Files:

- `config.toml` — deliberately empty config.
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

Format specifier preservation is requested by built-in xcode-strings and checked against real catalog responses during execution. Dry-run cannot validate a response. A live model may still return a rejected result.

## Command 1: Conflicting source warning; catalog source still English.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --to fr --config config.toml --from de Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/Localizable.xcstrings
Mode: .xcstrings catalog translation (per segment)
Preset: xcode-strings
Preset origin: implicit catalog default
Source lang: English (en); catalog sourceLanguage
Target lang: French (fr)
Target origin: CLI --to
Provider: openai
Model: gpt-4o-mini
System prompt origin: built-in preset xcode-strings
User prompt origin: built-in preset xcode-strings
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
You are a skilled translator with extensive experience in translating English UI text to French for macOS and iOS applications.
The text was taken from an Xcode string catalog (.xcstrings).
Preserve all format specifiers such as %@, %lld, %.2f, %1$@, %2$@, %3$@, %1$lld, %2$lld and similar placeholders. Place them at the contextually appropriate position in the translated string.
If there is markdown formatting, keep it intact.
Preserve the meaning and tone appropriate for a macOS/iOS user interface.
If multiple valid translations exist, use the context provided to choose the most natural and idiomatic option for a native French speaker.
Only output the translation. Do not include explanations, original text, or wrapping backticks.

--- USER PROMPT ---
Translate the following English UI string to French.
Additional context: Developer comment: Greeting on the welcome screen.

<source_text>
Hello %@
</source_text>

--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr:

```text
Warning: Localizable.xcstrings: catalog sourceLanguage 'English (en)' overrides configured source 'German (de)'. --from and preset/config source settings do not change catalog source selection.
```

## Command 2: Source target gives zero requests.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --config config.toml --to en Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/Localizable.xcstrings
Mode: .xcstrings catalog translation (per segment)
Preset: xcode-strings
Preset origin: implicit catalog default
Source lang: English (en); catalog sourceLanguage
Target lang: English (en)
Target origin: CLI --to
Provider: openai
Model: gpt-4o-mini
System prompt origin: built-in preset xcode-strings
User prompt origin: built-in preset xcode-strings
Max concurrent catalog requests: 1
Pending segments: 0
No pending segments; no translation requests would be sent.
```

Expected stderr: empty.

## Command 3: Forced source target rejected.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --config config.toml --to en --retranslate Localizable.xcstrings
```

Expected exit status: `1`.

Expected stdout: empty; no messages are rendered.

Expected stderr:

```text
--retranslate cannot target catalog sourceLanguage 'en'; source localizations are preserved.
One or more files failed.
```

## Command 4: General {format} renders markdown without changing catalog route.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset general --format markdown Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/Localizable.xcstrings
Mode: .xcstrings catalog translation (per segment)
Preset: general
Preset origin: CLI --preset
Source lang: English (en); catalog sourceLanguage
Target lang: French (fr)
Target origin: CLI --to
Provider: openai
Model: gpt-4o-mini
System prompt origin: built-in preset general
User prompt origin: built-in preset general
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
You are a skilled translator with expertise in translating English to French, preserving the original meaning, tone, and nuance.
Maintain any formatting present in the source text.
Only output the translation. Do not include explanations, commentary, or original text.
Do not wrap your output in backticks or code blocks.

--- USER PROMPT ---
Translate the following markdown from English to French.
Additional context: Developer comment: Greeting on the welcome screen.

<source_text>
Hello %@
</source_text>

--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr:

```text
Warning: Localizable.xcstrings: format 'markdown' affects segment {format} only; .xcstrings files always use catalog translation.
```

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
