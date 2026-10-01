# Metadata customization affects preset selection

Only `presets.general.provider` and `.model` are configured, without defaults.preset. Even this metadata-only general customization suppresses implicit xcode-strings selection. Both prompt fields fall back to original built-in general. This command omits provider/model flags so the selected preset supplies ollama/docs-example-model.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/22-catalog-metadata-only-preset
```

Files:

- `config.toml`
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: General metadata selection.

```sh
translate --dry-run --from en --to fr --config config.toml Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/Localizable.xcstrings
Mode: .xcstrings catalog translation (per segment)
Preset: general
Preset origin: customized config default preset
Source lang: English (en); catalog sourceLanguage
Target lang: French (fr)
Target origin: CLI --to
Provider: ollama
Model: docs-example-model
System prompt origin: built-in preset general
User prompt origin: built-in preset general
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       ollama
Model:          docs-example-model
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
