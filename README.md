# translate

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/atacan/translate)

`translate` is a command-line tool for translating text and files with configurable providers, prompt presets, and TOML-based configuration.

LLM-backed providers (`openai`, `anthropic`, `gemini`, `open-responses`, `ollama`, `openai-compatible`, and `apple-intelligence`) use [`AnyLanguageModel`](https://github.com/mattt/AnyLanguageModel) as the model/provider abstraction layer.

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

### Install the coding agent skill

The optional `translate-cli` skill provides usage guidance for coding agents. Install it with [`npx skills`](https://github.com/vercel-labs/skills):

```bash
npx skills add atacan/translate --skill translate-cli
```

For more detail alongside the skill, explore the [runnable examples](examples/README.md): local configs, exact rendered prompts, and explanations of which settings take precedence.

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

Explore [31 runnable prompt and config walkthroughs](examples/README.md), each with a local `--config`, dry-run commands, and complete expected messages. They cover text, Xcode catalogs, prompt precedence, file paths, diagnostics, and promptless providers without API calls or credentials.

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

### Gemini

```bash
export GEMINI_API_KEY="your_api_key"
translate --provider gemini --text --to en "Merhaba dunya"
```

### Open Responses

```bash
export OPEN_RESPONSES_API_KEY="your_api_key"
translate --provider open-responses --text --to en "Merhaba dunya"
```

### Ollama (local)

```bash
translate --provider ollama --model llama3.2 --text --to en "Merhaba dunya"
```

### OpenAI-compatible endpoint

Use ad-hoc flags:

```bash
translate --base-url http://localhost:1234/v1 --api-key dummy --model llama3.1 --text --to en "Merhaba dunya"
```

Or configure named endpoints (recommended):

```bash
translate config set providers.openai-compatible.lmstudio.base_url http://localhost:1234/v1
translate config set providers.openai-compatible.lmstudio.model llama3.1
translate config set providers.openai-compatible.lmstudio.api_key dummy
translate --provider lmstudio --text --to en "Merhaba dunya"
```

### DeepL

```bash
export DEEPL_API_KEY="your_api_key"
translate --provider deepl --text --to en "Merhaba dunya"
```

Notes:

- `--base-url` without `--provider` automatically uses `openai-compatible`.
- `openai-compatible` now requires an API key (some local endpoints may accept any placeholder string).
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

Single file to stdout with streaming enabled:

```bash
translate --stream --to de docs/input.md
```

Streaming control note:

- `--stream` forces streaming on for the current command.
- `--no-stream` forces streaming off for the current command.
- They are both needed because `defaults.stream` can enable streaming globally in `config.toml`, and each command still needs a direct way to override that default in either direction.

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

`presets list` marks built-ins overridden in config. `presets which` reports the configured/text default without inspecting input; catalogs may instead select the implicit `xcode-strings` default. `presets show` and dry-run report each prompt field's origin.

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

Placeholders are replaced with values for the current input or catalog segment:

| Placeholder | Meaning and possible values |
| --- | --- |
| `{from}` | Source language's English display name, such as `English` or `Traditional Chinese`. With `--from auto`, this becomes the literal phrase `the source language`. Catalogs use their `sourceLanguage`. |
| `{to}` | Target language's English display name, such as `French`. Language settings accept recognized names (`French`), ISO 639-1 codes (`fr`), or BCP 47 tags (`zh-TW`); `auto` is allowed only for the source. The prompt receives the display name. |
| `{text}` | The source text to translate, including its existing whitespace and line breaks. For a catalog, this is one selected segment's text. |
| `{context}` | Free-form text supplied with `--context`, trimmed of leading/trailing whitespace. Empty when no context is supplied. For catalogs, it combines CLI context and the entry's developer comment on separate lines labeled `CLI context:` and `Developer comment:`; absent parts are omitted. |
| `{context_block}` | Empty when `{context}` is empty. Otherwise, a leading newline followed by `Additional context: ` and the same context text. Use it to append optional context to an instruction without leaving a label when context is absent. |
| `{filename}` | Input file's basename, including its extension, such as `notes.md` or `Localizable.xcstrings`. Empty for inline text and stdin. |
| `{format}` | Resolved source-content hint: exactly `text`, `markdown`, or `HTML` (capitalized). Resolution is explained below. |
| `{string_key}` | Catalog entry's key, for example `welcome.title`. Empty for non-catalog input. |
| `{comment}` | Catalog entry's developer comment as written. Empty when the comment is missing or input is not a catalog. |
| `{segment}` | Catalog segment label: `stringUnit`, `stringSet[index]` (zero-based index, for example `stringSet[0]`), or `variation[path]` (for example `variation[variations.plural.one]`). Empty for non-catalog input. |

`--format` accepts exactly `auto`, `text`, `markdown`, or `html`. The same values are valid for `format` in TOML defaults/presets. Explicit `text` and `markdown` render unchanged; `html` renders as `HTML`. With `auto`, the file extension determines the value:

| Input | `{format}` value |
| --- | --- |
| `.md`, `.markdown`, `.mdx` files | `markdown` |
| `.html`, `.htm` files | `HTML` |
| Other extensions, including `.xcstrings`, or inline text/stdin | `text` |

Extensions are matched case-insensitively. `auto` is a selection setting; the rendered placeholder always contains one of the three resolved values. The hint describes the content to the LLM; catalog files continue to use per-segment catalog translation regardless of the hint.

For example, with `--to fr --context "Settings screen"`, this user template:

```text
Translate to {to}.{context_block}

{text}
```

renders for the source text `Save changes` as:

```text
Translate to French.
Additional context: Settings screen

Save changes
```

Without `--context`, the `Additional context:` line disappears. If you want your own label or layout, use `{context}` instead, for example `Screen: {context}`; that label remains even when context is empty. See the [catalog context walkthrough](examples/21-catalog-overrides-and-context/README.md) for both placeholders with developer comments.

Templates are rendered once: placeholder-like text in source, context, filenames, or metadata is preserved literally. Context retains the usual leading/trailing whitespace trimming. Double-braced text such as `{{to}}` is preserved as written, including both braces.

For providers that use prompts, the user template must contain non-whitespace text, and `{text}` must appear in either the system or user template. Invalid templates fail before a translation request. Unsupported identifier-shaped tokens such as `{target_language}` produce a warning and remain literal; ordinary JSON and CSS braces do not produce warnings.

Each CLI prompt override replaces only its corresponding preset field. Within a preset, inline prompt text takes precedence over its prompt file. Missing fields in a preset named like a built-in fall back to that built-in; other custom names fall back to the original built-in `general`, even when `[presets.general]` is customized. Relative TOML `system_prompt_file` and `user_prompt_file` paths resolve beside the config file. CLI `@file` paths resolve from the invocation working directory. Absolute and `~/` paths keep their usual meaning. Only selected prompt files are read. A preset that changes only provider, model, or other metadata still uses default prompts. `--no-lang` suppresses the missing-language warning for customized prompts; it does not suppress validation or unknown-token warnings. Promptless providers ignore unused templates.

## Xcode string catalogs

`.xcstrings` files are translated one segment at a time using the same prompt templates and independent system/user override precedence as text input. Catalogs default to `xcode-strings` unless a CLI preset, explicit config `defaults.preset`, or customized default/general preset selects another preset. Explicit `general` wins. Mixed batches choose defaults and preset provider/model/target settings per input route; default filename suffixes follow each target.

```bash
translate --to fr Localizable.xcstrings
translate --preset general --to de --context "Settings screen" Localizable.xcstrings
translate --dry-run --in-place --to fr notes.md Localizable.xcstrings
```

Catalog `sourceLanguage` determines the source language; conflicting non-auto CLI/config/preset source settings warn. `--format` affects each segment's `{format}` only and cannot change catalog routing. `{filename}` is the basename, `{string_key}` is the entry key, `{comment}` is its developer comment, and `{segment}` identifies `stringUnit`, `stringSet[index]`, or `variation[path]`. `{context}` and `{context_block}` combine CLI context and developer comments with distinct `CLI context:` and `Developer comment:` labels.

Catalog selection includes missing or empty target values and nonempty targets marked `new` or `needs_review` for string units, string sets, plural/device variants, and substitutions. Nonempty completed or unknown states are preserved by default. `--retranslate` selects all eligible target segments, including completed translations; it requires a catalog and applies only to catalogs in mixed batches. Catalog source localizations are preserved: targeting `sourceLanguage` yields no pending work, and forced source retranslation fails.

```bash
translate --dry-run --retranslate --to fr Localizable.xcstrings
translate --retranslate --in-place --yes --to fr Localizable.xcstrings
```

Every translated segment is checked for printf/Xcode placeholder identity, type, argument position, formatting, and multiplicity, including escaped `%%`, star width/precision arguments, and `%#@name@` references. Valid positional reordering is allowed, including implicit source arguments changed to explicit target numbering. Mixing numbered and sequential argument consumption is rejected. Invalid output is reported as a segment failure and retains the original target slot. Best-effort runs write valid segments while returning failure status; partial string sets remain incomplete. Unmodeled catalog metadata is preserved.

Catalog dry-run parses files and previews up to three actual pending segment requests per catalog with source/target metadata, preset selection and prompt origins, and provider/model. It reports zero pending segments and fails for malformed catalogs. Mixed batches show both paths. Dry-run never calls APIs, requests overwrite confirmation, or writes files, including in-place runs without `--yes`.

## Configuration

Default config path:

- `~/.config/translate/config.toml`

Override config path:

- CLI: `--config /path/to/config.toml`
- Environment: `TRANSLATE_CONFIG=/path/to/config.toml`

Exactly one config is loaded: `--config` takes precedence over `TRANSLATE_CONFIG`, then the default path. There is no project discovery or config stacking. A missing implicit default is valid and uses built-in defaults. A missing explicitly selected path fails translation and read-only `config`/`presets` commands. `config path` still prints missing paths; `config set` and `config edit` create the selected file and parent directories. `config unset` on a missing file does nothing. Unknown keys and wrong types in defaults/presets produce warnings naming the key and expected setting, without printing its value.

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
translate config set defaults.stream true
translate config set defaults.jobs 4
translate config unset defaults.jobs
```

Why both `--stream` and `--no-stream` exist:

- Config can set a global default with `defaults.stream = true` or `false`.
- `--stream` is the per-command override that forces streaming on.
- `--no-stream` is the per-command override that forces streaming off.
- Without both flags, users with a global preference would lose the ability to invert it for one command without editing config.

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
stream = false
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

Network settings above apply to providers using the custom HTTP path (currently DeepL). `AnyLanguageModel`-backed LLM providers use the library's networking behavior.

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
- `--retranslate` replace existing catalog target segments (catalogs only in mixed input)
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
