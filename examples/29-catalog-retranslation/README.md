# Retranslate completed catalog segments

Normal mode has zero requests because the base unit, device variation, and substitution plural all have completed nonempty French values. --retranslate selects all three, preserving catalog source selection. The forced preview shows every request and its segment label.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/29-catalog-retranslation
```

Files:

- `config.toml` — deliberately empty config.
- `Localizable.xcstrings`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

In real execution, successful segments replace only their selected French values and become translated. Failed segments retain their previous values; source localizations and unrelated metadata are preserved. Format validation can reject missing/changed format arguments. Dry-run demonstrates selection and messages only: it cannot prove response validity, failure preservation, or model compliance.

## Command 1: Completed values skipped.

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
System prompt origin: built-in preset xcode-strings
User prompt origin: built-in preset xcode-strings
Max concurrent catalog requests: 1
Pending segments: 0
No pending segments; no translation requests would be sent.
```

Expected stderr: empty.

## Command 2: Forced base, device, and substitution requests.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --retranslate Localizable.xcstrings
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
Pending segments: 3
String key: entry; segment: stringUnit
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
Additional context: Developer comment: Count and greeting UI.

<source_text>
Hello %@
</source_text>

--- INPUT (first 500 chars) ---
Hello %@
String key: entry; segment: variation[substitutions.count.variations.plural.other]
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
Additional context: Developer comment: Count and greeting UI.

<source_text>
Many %lld
</source_text>

--- INPUT (first 500 chars) ---
Many %lld
String key: entry; segment: variation[variations.device.iphone]
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
Additional context: Developer comment: Count and greeting UI.

<source_text>
Phone %@
</source_text>

--- INPUT (first 500 chars) ---
Phone %@
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
