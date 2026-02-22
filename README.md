# translate

`translate` is a command-line tool for translating text and files with configurable providers, prompt presets, and TOML-based configuration.

## Installation

Install via Homebrew tap:

```bash
brew tap atacan/tap
brew install atacan/tap/translate
```

Verify:

```bash
translate --version
translate --help
```

Build from source (alternative):

```bash
swift build -c release
sudo install -m 755 "$(swift build -c release --show-bin-path)/translate" /usr/local/bin/translate
```

Release and Homebrew automation docs: `docs/release.md`

## Quick Start

These examples assume you already configured a provider (see Provider Setup below).

Important: put options before positional text/file arguments (for example, `translate --to de README.md`, not `translate README.md --to de`).

Translate inline text:

```bash
translate --text --from tr --to en "Merhaba dunya"
```

Auto-detect source language:

```bash
translate --text --to fr "Hello world"
```

Preview resolved prompts and settings without sending a request:

```bash
translate --provider ollama --text --to en --dry-run "Merhaba dunya"
```

## Provider Setup

Defaults:

- Default provider: `openai`
- Default model (openai): `gpt-4o-mini`
- Default source language: `auto`
- Default target language: `en`

### OpenAI (default)

```bash
export OPENAI_API_KEY="your_api_key"
translate --text --to en "Merhaba dunya"
```

### Anthropic

```bash
export ANTHROPIC_API_KEY="your_api_key"
translate --provider anthropic --text --to en "Merhaba dunya"
```

### Ollama (local)

```bash
translate --provider ollama --model llama3.2 --text --to en "Merhaba dunya"
```

### OpenAI-compatible endpoint

Use ad-hoc flags:

```bash
translate --base-url http://localhost:1234/v1 --model llama3.1 --text --to en "Merhaba dunya"
```

Or configure named endpoints (recommended):

```bash
translate config set providers.openai-compatible.lmstudio.base_url http://localhost:1234/v1
translate config set providers.openai-compatible.lmstudio.model llama3.1
translate --provider lmstudio --text --to en "Merhaba dunya"
```

### DeepL

```bash
export DEEPL_API_KEY="your_api_key"
translate --provider deepl --text --to en "Merhaba dunya"
```

Notes:

- `--base-url` without `--provider` automatically uses `openai-compatible`.
- `--provider openai` and `--base-url` cannot be used together.
- `apple-translate` and `apple-intelligence` are available on macOS 26+.

## Input Modes

`translate` accepts input from positional arguments, files, globs, or stdin.

### Inline text

Without `--text`, a single positional argument is treated as a file if that path exists; otherwise it is treated as text.

```bash
translate --to es "How are you?"
```

Use `--text` to force literal text mode:

```bash
translate --text --to es "README.md"
```

### File input

Single file to stdout:

```bash
translate --to de docs/input.md
```

Single file to explicit output path:

```bash
translate --to de --output docs/input.de.md docs/input.md
```

In-place overwrite:

```bash
translate --to de --in-place docs/input.md
```

### Multiple files and glob patterns

Use shell-expanded file lists:

```bash
translate --to fr --suffix _fr docs/*.md
```

Or quote patterns so `translate` expands the glob:

```bash
translate --to fr "docs/**/*.md"
```

Behavior for multiple files or globs:

- Output is written per-file.
- Default suffix is `_<LANG>` (for example `_FR`).
- `--output` is only valid for a single input file.
- Use `--jobs` to process multiple files concurrently.

### Stdin

```bash
echo "Merhaba dunya" | translate --to en
```

## Presets

Built-in presets:

- `general`
- `markdown`
- `xcode-strings`
- `legal`
- `ui`

List presets:

```bash
translate presets list
```

Show preset prompts:

```bash
translate presets show markdown
```

Use a preset:

```bash
translate --preset markdown --to fr README.md
```

## Prompt Customization

Override prompt templates directly:

```bash
translate --text --to en \
  --system-prompt "You are a strict translator from {from} to {to}." \
  --user-prompt "Translate this {format}: {text}" \
  "Merhaba dunya"
```

Load prompt template from files with `@path`:

```bash
translate --text --to en \
  --system-prompt @./prompts/system.txt \
  --user-prompt @./prompts/user.txt \
  "Merhaba dunya"
```

Available placeholders:

- `{from}`
- `{to}`
- `{text}`
- `{context}`
- `{context_block}`
- `{filename}`
- `{format}`

## Configuration

Default config path:

- `~/.config/translate/config.toml`

Override config path:

- CLI: `--config /path/to/config.toml`
- Environment: `TRANSLATE_CONFIG=/path/to/config.toml`

Inspect config:

```bash
translate config path
translate config show
translate config get defaults.provider
```

Set and unset values:

```bash
translate config set defaults.provider anthropic
translate config set defaults.to fr
translate config set defaults.jobs 4
translate config unset defaults.jobs
```

Edit in `$EDITOR`:

```bash
translate config edit
```

Example `config.toml`:

```toml
[defaults]
provider = "openai"
from = "auto"
to = "en"
preset = "general"
format = "auto"
yes = false
jobs = 1

[network]
timeout_seconds = 120
retries = 3
retry_base_delay_seconds = 1

[providers.openai]
model = "gpt-4o-mini"

[providers.openai-compatible.lmstudio]
base_url = "http://localhost:1234/v1"
model = "llama3.1"
api_key = ""

[presets.markdown]
user_prompt = "Translate this markdown from {from} to {to}: {text}"
```

## Flags Reference

Main translation options:

- `--text` force literal positional text mode
- `--output, -o <path>` write output to a file
- `--in-place, -i` overwrite source files
- `--suffix <suffix>` suffix for per-file outputs
- `--yes, -y` skip overwrite confirmations
- `--jobs, -j <n>` parallel file jobs
- `--from, -f <lang>` source language (`auto` allowed)
- `--to, -t <lang>` target language (`auto` not allowed)
- `--provider, -p <name>` provider
- `--model, -m <id>` model identifier
- `--base-url <url>` openai-compatible base URL
- `--api-key <key>` API key override
- `--preset <name>` prompt preset
- `--system-prompt <text|@file>` system prompt override
- `--user-prompt <text|@file>` user prompt override
- `--context, -c <text>` extra context
- `--format <auto|text|markdown|html>` format hint
- `--dry-run` print resolved prompts/provider/model and exit
- `--quiet, -q` suppress warnings
- `--verbose, -v` verbose diagnostics

Subcommands:

- `translate config ...`
- `translate presets ...`

## Exit Codes

- `0` success
- `1` runtime error
- `2` invalid arguments
- `3` aborted by user

## Troubleshooting

`OPENAI_API_KEY is required for provider 'openai'`

- Set `OPENAI_API_KEY`, switch provider, or change `defaults.provider`.

`'auto' is not valid for --to`

- Use a concrete target language such as `--to fr`.

`--output can only be used with a single input`

- Use one input file with `--output`, or use `--suffix` for multi-file workflows.

`No files matched the pattern ...`

- Quote glob patterns when you want `translate` to expand them itself, and verify paths.

## Example Script

An example script for running the compiled binary directly is available at:

- `examples/run-translation-from-build.sh`
