# Use preset prompt files

Custom `demo` supplies both prompt files. File paths are resolved relative to the selected config file. Each file ends with a newline, which remains part of the rendered message.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/05-custom-file-preset
```

Files:

- `config.toml`
- `system.txt`
- `user.txt`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Two preset files.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset demo --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: demo
System prompt origin: user preset demo file <example-directory>/system.txt
User prompt origin: user preset demo file <example-directory>/user.txt
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
FILE SYSTEM: Translate English to French.


--- USER PROMPT ---
FILE USER:
Hello world


--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
