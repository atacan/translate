# Skip prompts for a promptless provider

DeepL is promptless. Selected demo metadata still applies, but broken/missing preset prompt files and CLI prompt files are skipped, and the empty configured user field is not validated. No system or user message is sent. The printer displays empty prompt sections only; source text is the provider input.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/31-promptless-provider
```

Files:

- `config.toml`
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

Warnings identify ignored prompt flags/templates. --dry-run bypasses credentials and API calls, including DeepL credentials. The shown empty sections are not messages sent to DeepL.

## Command 1: Promptless text preview.

```sh
translate --dry-run --from en --to fr --config config.toml --preset demo --provider deepl --system-prompt @missing-cli-system.txt --user-prompt @missing-cli-user.txt --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: unused (promptless provider)
User prompt origin: unused (promptless provider)
=== DRY RUN ===

Provider:       deepl
Model:          (provider default)
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---


--- USER PROMPT ---


--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr:

```text
Warning: --system-prompt is ignored when using deepl. This provider does not support custom prompts.
Warning: --user-prompt is ignored when using deepl. This provider does not support custom prompts.
Warning: The prompt portion of --preset is ignored when using deepl; preset provider/model/language settings still apply.
Warning: Prompt templates in config preset 'demo' are ignored when using deepl; preset metadata still applies.
```

## Command 2: Promptless catalog preview.

```sh
translate --dry-run --from en --to fr --config config.toml --preset demo --provider deepl --system-prompt @missing-cli-system.txt --user-prompt @missing-cli-user.txt Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/Localizable.xcstrings
Mode: .xcstrings catalog translation (per segment)
Preset: demo
Preset origin: CLI --preset
Source lang: English (en); catalog sourceLanguage
Target lang: French (fr)
Target origin: CLI --to
Provider: deepl
Model: (provider default)
System prompt origin: unused (promptless provider)
User prompt origin: unused (promptless provider)
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       deepl
Model:          (provider default)
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---


--- USER PROMPT ---


--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr:

```text
Warning: --system-prompt is ignored when using deepl. This provider does not support custom prompts.
Warning: --user-prompt is ignored when using deepl. This provider does not support custom prompts.
Warning: The prompt portion of --preset is ignored when using deepl; preset provider/model/language settings still apply.
Warning: Prompt templates in config preset 'demo' are ignored when using deepl; preset metadata still applies.
```

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
