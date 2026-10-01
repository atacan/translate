# CLI prompt files win

CLI `@system.txt` and `@user.txt` override demo fields. CLI file paths are relative to the working directory.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/11-cli-file-prompts
```

Files:

- `config.toml`
- `system.txt`
- `user.txt`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Both CLI file fields.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset demo --system-prompt @system.txt --user-prompt @user.txt --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: CLI file system.txt
User prompt origin: CLI file user.txt
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
