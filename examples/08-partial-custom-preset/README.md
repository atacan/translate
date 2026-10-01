# Fall back from a partial custom preset

The selected new preset `demo` has only a system field. Its user field falls back to the original built-in general template, even though this config also customizes `presets.general.user_prompt`. Configured general is not a parent preset.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/08-partial-custom-preset
```

Files:

- `config.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Demo uses original general user fallback.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset demo --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: user preset demo inline
User prompt origin: built-in preset general
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CONFIG SYSTEM: Translate English to French.

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
