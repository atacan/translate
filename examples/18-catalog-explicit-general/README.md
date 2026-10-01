# Explicitly select general for a catalog

Either CLI `--preset general` or config `defaults.preset = "general"` prevents implicit xcode-strings selection. Both cases use original built-in general fields.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/18-catalog-explicit-general
```

Files:

- `config.toml` — deliberately empty config.
- `Localizable.xcstrings`
- `general.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: CLI general.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset general Localizable.xcstrings
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
Translate the following text from English to French.
Additional context: Developer comment: Greeting on the welcome screen.

<source_text>
Hello %@
</source_text>

--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr: empty.

## Command 2: Config default general.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config general.toml Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/Localizable.xcstrings
Mode: .xcstrings catalog translation (per segment)
Preset: general
Preset origin: config defaults.preset
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
Translate the following text from English to French.
Additional context: Developer comment: Greeting on the welcome screen.

<source_text>
Hello %@
</source_text>

--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
