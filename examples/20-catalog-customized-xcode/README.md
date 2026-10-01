# Customize xcode-strings with files

The empty selector still chooses implicit xcode-strings, then the configured xcode-strings prompt file fields shadow both original built-in fields.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/20-catalog-customized-xcode
```

Files:

- `config.toml`
- `system.txt`
- `user.txt`
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Implicit xcode-strings with config prompt files.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml Localizable.xcstrings
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
System prompt origin: user preset xcode-strings file <example-directory>/system.txt
User prompt origin: user preset xcode-strings file <example-directory>/user.txt
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CATALOG FILE SYSTEM: English to French.


--- USER PROMPT ---
CATALOG FILE USER: Hello %@
Additional context: Developer comment: Greeting on the welcome screen.


--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
