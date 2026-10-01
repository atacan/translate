# Select pending catalog segments

Missing and empty French units are pending regardless of completion state; nonempty new and needs_review units are also pending. Nonempty translated units and shouldTranslate=false entries are skipped. Each fixture yields two requests; all are shown. Variant/substitution selection is illustrated in example 29.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/28-catalog-pending-selection
```

Files:

- `config.toml` — deliberately empty config.
- `missing-and-empty.xcstrings`
- `new-and-review.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Missing and empty selected; completed and skip excluded.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml missing-and-empty.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/missing-and-empty.xcstrings
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
Pending segments: 2
String key: empty; segment: stringUnit
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

<source_text>
Empty target
</source_text>

--- INPUT (first 500 chars) ---
Empty target
String key: missing; segment: stringUnit
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

<source_text>
Missing target
</source_text>

--- INPUT (first 500 chars) ---
Missing target
```

Expected stderr: empty.

## Command 2: New and needs_review selected; completed excluded.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml new-and-review.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
=== CATALOG DRY RUN ===
File: <example-directory>/new-and-review.xcstrings
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
Pending segments: 2
String key: needs_review; segment: stringUnit
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

<source_text>
Review target
</source_text>

--- INPUT (first 500 chars) ---
Review target
String key: new; segment: stringUnit
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

<source_text>
New target
</source_text>

--- INPUT (first 500 chars) ---
New target
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
