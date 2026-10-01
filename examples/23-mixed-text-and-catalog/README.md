# Resolve mixed input prompts independently

The same empty config uses built-in general for the one text file and implicit built-in xcode-strings for the one catalog. Both get English to French, but only catalog context labels the developer comment. Mixed live execution would create suffixed outputs `source_fr.txt` and `Localizable_fr.xcstrings`.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/23-mixed-text-and-catalog
```

Files:

- `config.toml` — deliberately empty config.
- `Localizable.xcstrings`
- `source.txt`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: One text request and one catalog request.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml source.txt Localizable.xcstrings
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
File: <example-directory>/source.txt
Mode: text translation
Preset: general
System prompt origin: built-in preset general
User prompt origin: built-in preset general
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

<source_text>
Hello world

</source_text>

--- INPUT (first 500 chars) ---
Hello world

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

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
