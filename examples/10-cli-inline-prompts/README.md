# CLI inline prompts win

Both CLI fields override selected `demo` config fields. Preset selection remains demo; origins are CLI inline.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/10-cli-inline-prompts
```

Files:

- `config.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Both CLI inline fields.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset demo --system-prompt 'CLI SYSTEM: Translate {from} to {to}.' --user-prompt 'CLI USER: {text}{context_block}' --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: CLI inline
User prompt origin: CLI inline
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CLI SYSTEM: Translate English to French.

--- USER PROMPT ---
CLI USER: Hello world

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
