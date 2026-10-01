# Compare CLI and config file path bases

The config points to `config/prompts/...`. CLI `@prompts/...` overrides both and reads the distinct files under the current directory. Config paths remain relative to the config; CLI paths remain relative to cwd.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/14-cli-file-over-config-file
```

Files:

- `config/config.toml`
- `config/prompts/system.txt`
- `config/prompts/user.txt`
- `prompts/system.txt`
- `prompts/user.txt`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: CLI files override config files.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config/config.toml --preset demo --system-prompt @prompts/system.txt --user-prompt @prompts/user.txt --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: CLI file prompts/system.txt
User prompt origin: CLI file prompts/user.txt
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
CLI FILE SYSTEM: English to French.


--- USER PROMPT ---
CLI FILE USER: Hello world


--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
