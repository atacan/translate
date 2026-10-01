# Render catalog metadata and context

CLI prompts override both implicit xcode-strings fields. Each real request renders the string key, comment, segment, filename, format, text, and context. Combined context labels CLI context and developer comment; {comment} contains only the developer comment.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/21-catalog-overrides-and-context
```

Files:

- `config.toml` — deliberately empty config.
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: CLI metadata templates.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --context 'Friendly welcome.' --system-prompt 'CLI SYSTEM: {from} to {to}; file={filename}; format={format}.' --user-prompt 'key={string_key}
comment={comment}
segment={segment}
context={context}
block:{context_block}
text={text}' Localizable.xcstrings
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
System prompt origin: CLI inline
User prompt origin: CLI inline
Max concurrent catalog requests: 1
Pending segments: 1
String key: greeting; segment: stringUnit
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CLI SYSTEM: English to French; file=Localizable.xcstrings; format=text.

--- USER PROMPT ---
key=greeting
comment=Greeting on the welcome screen.
segment=stringUnit
context=CLI context: Friendly welcome.
Developer comment: Greeting on the welcome screen.
block:
Additional context: CLI context: Friendly welcome.
Developer comment: Greeting on the welcome screen.
text=Hello %@

--- INPUT (first 500 chars) ---
Hello %@
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
