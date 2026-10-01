# Customize the catalog default general

The config has no defaults.preset, but contains `presets.general`. That customization of the configured default suppresses implicit xcode-strings selection. Both fields are general config inline values.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/19-catalog-customized-general
```

Files:

- `config.toml`
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Customized config default general.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml Localizable.xcstrings
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
Provider: openai
Model: gpt-4o-mini
System prompt origin: user preset general inline
User prompt origin: user preset general inline
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CONFIG SYSTEM: Translate English to French.

--- USER PROMPT ---
CONFIG USER: Hello %@
Additional context: Developer comment: Greeting on the welcome screen.

--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
