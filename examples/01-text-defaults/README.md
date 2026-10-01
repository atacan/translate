# Text with built-in defaults

An explicitly selected empty config has no preset selector or customization. Text therefore selects built-in `general`; both fields come from that preset.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/01-text-defaults
```

Files:

- `config.toml` — deliberately empty config.

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Built-in general supplies both fields.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
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
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
