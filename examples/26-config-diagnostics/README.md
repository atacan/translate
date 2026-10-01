# Diagnose explicitly selected configs

A missing --config file is an error. Unknown keys and wrong value types warn while valid fields still resolve. The typo user_promt is ignored, so selected demo user falls back to original built-in general; the invalid general system value is also ignored. Warnings report key paths and types, without echoing values.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/26-config-diagnostics
```

Files:

- `config.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Missing explicitly selected config.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config missing.toml --text 'Hello world'
```

Expected exit status: `1`.

Expected stdout: empty; no messages are rendered.

Expected stderr:

```text
Config file '<example-directory>/missing.toml' not found. Check --config or TRANSLATE_CONFIG, or create it with translate config set/edit.
```

## Command 2: Warnings and successful field fallback.

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

Expected stderr:

```text
Warning: Config key 'defaults.stream' must be a boolean; the value is ignored.
Warning: Unknown config key 'presets.demo.user_promt'. Supported keys: description, format, from, model, provider, system_prompt, system_prompt_file, to, user_prompt, user_prompt_file.
Warning: Config key 'presets.general.system_prompt' must be a string; the value is ignored.
```

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
