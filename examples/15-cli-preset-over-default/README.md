# CLI preset wins over config default

Config defaults to custom demo. CLI `--preset legal` selects built-in legal instead, so neither demo prompt is used.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/15-cli-preset-over-default
```

Files:

- `config.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: CLI legal overrides default demo.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset legal --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: legal
System prompt origin: built-in preset legal
User prompt origin: built-in preset legal
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
You are a professional legal translator with expertise in translating legal and formal documents from English to French.
Your translation must be faithful to the source: do not paraphrase, simplify, omit, or add content.
Preserve the formal register, legal terminology, and document structure.
Only output the translated text. Do not include explanations, commentary, or wrapping backticks.

--- USER PROMPT ---
Translate the following legal text from English to French.

<source_text>
Hello world
</source_text>

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
