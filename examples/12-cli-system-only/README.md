# Override only the system field

CLI system wins; the selected demo inline user remains active. Overrides are per field.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/12-cli-system-only
```

Files:

- `config.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: CLI system and config user.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset demo --system-prompt 'CLI SYSTEM: Translate {from} to {to}.' --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: CLI inline
User prompt origin: user preset demo inline
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CLI SYSTEM: Translate English to French.

--- USER PROMPT ---
CONFIG USER: Hello world

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
