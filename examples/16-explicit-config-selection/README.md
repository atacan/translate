# Choose one local config explicitly

Each command selects exactly one named local config with `--config`. Alpha supplies both general fields; beta supplies only system, so beta user falls back to original built-in general. Alpha is not merged into beta, and the neighboring config.toml is not discovered.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/16-explicit-config-selection
```

Files:

- `alpha.toml`
- `beta.toml`
- `config.toml`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Alpha selected; both alpha inline fields.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config alpha.toml --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: general
System prompt origin: user preset general inline
User prompt origin: user preset general inline
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
ALPHA SYSTEM: English to French.

--- USER PROMPT ---
ALPHA USER: Hello world

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

## Command 2: Beta selected; beta system and built-in general user.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config beta.toml --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: general
System prompt origin: user preset general inline
User prompt origin: built-in preset general
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
BETA SYSTEM: English to French.

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
