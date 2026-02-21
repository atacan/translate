# `translate` — CLI Tool Specification

**Version:** 1.2
**Purpose:** This document is the complete specification for the `translate` command-line tool. It covers all commands, flags, arguments, behaviors, validation rules, configuration, prompt templating, and provider handling. The developer receiving this document has full freedom to choose the implementation language, toolchain, and packaging strategy.

**Changelog from v1.1:**
- Fixed contradiction: named endpoint resolution order now matches collision rule (built-ins always win)
- Removed `--timeout` reference from error message; replaced with `config set` guidance
- Added missing flag conflict rules: `--in-place` + `--output`, `--in-place` + `--suffix`, `--suffix` with single file, `--jobs` with non-file input, `--to auto`
- Defined invalid language code error message
- Moved `--text` / `-T` to INPUT section in help text
- Removed short flag `-T` from `--text` to avoid `-t` / `-T` case confusion; `--text` is now long-form only
- Fixed §7.3: removed `--context_block` from ignored flags list (it is a placeholder, not a CLI flag)
- Clarified `presets show`: displays raw templates with placeholders intact
- Added `--format` to ignored flags for prompt-less providers
- Defined `--to auto` as a hard error
- Addressed single-file glob output asymmetry: glob always uses file output mode
- Updated all default user prompts to use `<source_text>` XML tags instead of triple backticks to avoid delimiter collision
- Added extensionless file naming rule (§3.4)
- Added Apple Translate formatting note to Developer Notes

---

## Table of Contents

1. [Overview](#1-overview)
2. [Input Modes](#2-input-modes)
3. [Output Modes](#3-output-modes)
4. [Full Flag Reference](#4-full-flag-reference)
5. [Prompt Templating System](#5-prompt-templating-system)
6. [Presets](#6-presets)
7. [Providers](#7-providers)
8. [Configuration File](#8-configuration-file)
9. [The `config` Sub-command](#9-the-config-sub-command)
10. [The `presets` Sub-command](#10-the-presets-sub-command)
11. [Validation Rules and Error Handling](#11-validation-rules-and-error-handling)
12. [Behavior by Scenario](#12-behavior-by-scenario)
13. [Default Prompts](#13-default-prompts)
14. [Environment Variables](#14-environment-variables)
15. [Exit Codes](#15-exit-codes)
16. [Help Text](#16-help-text)
17. [Developer Notes](#17-developer-notes)

---

## 1. Overview

`translate` is a command-line tool for translating text and files using a variety of backends: large language model (LLM) APIs, Apple Translate (macOS system API), Apple Intelligence (macOS on-device AI), and DeepL. The tool is designed for developers, writers, and power users who need scriptable, configurable, high-quality translation with fine-grained control over the prompts and models used.

The binary is invoked as:

```
translate [INPUT] [OPTIONS]
translate <subcommand> [OPTIONS]
```

### Design Principles

- **Template-based prompts.** Languages and context are woven into prompts via named placeholders (`{from}`, `{to}`, `{text}`, `{context}`, etc.), not appended as afterthoughts.
- **Sensible defaults, full control.** Every option has a default so the tool works with minimal arguments, but every behavior can be overridden.
- **Layered configuration.** CLI flags → preset values → config `[defaults]` → built-in defaults (highest to lowest priority).
- **Provider-agnostic surface.** The CLI interface is identical regardless of provider; incompatible flags produce clear warnings or errors rather than silently misbehaving.
- **Composable and scriptable.** Supports stdin/stdout piping, cross-platform glob expansion, and dry-run mode.
- **Safe for automation.** The tool never blocks on interactive prompts in non-TTY environments.

---

## 2. Input Modes

The tool supports three mutually exclusive input modes. The mode is either detected automatically or forced explicitly with `--text`.

### 2.1 Inline Text

A string is passed directly as a positional argument and the tool detects it is not a path to an existing file, or the `--text` flag is used to force text mode explicitly.

```
translate "Bonjour le monde" --to en
translate --text document.md --to en    # translates the string "document.md", not the file
```

The `--text` flag exists to disambiguate cases where a string happens to match an existing filename in the current directory. Without `--text`, if a file named `document.md` exists, `translate document.md` would translate the file contents — not the literal string.

Output goes to **stdout** by default.

### 2.2 File Input

One or more file paths are passed as positional arguments and all resolve to existing files, or glob patterns that the tool itself expands.

```
translate document.md --to fr
translate *.md --to ja
translate file1.md file2.txt --to de
```

**Glob expansion:** The tool performs its own glob expansion on all platforms. It does not rely on the shell to expand patterns like `*.md`. This ensures consistent behavior on Windows (cmd.exe, PowerShell) and Unix alike. A glob pattern that matches zero files produces an error: `"No files matched the pattern '<pattern>'."`

**Glob always uses file output mode:** When the input is specified as a glob pattern (i.e. the positional argument contains wildcard characters such as `*`, `?`, or `[`), the tool always uses file output mode — even if the glob resolves to exactly one file. This prevents the surprising behavior where `translate *.md --to fr` outputs to stdout when only one `.md` file exists in the directory, but writes to disk when there are two. Users who need stdout from a single glob match should use `cat file.md | translate --to fr` or `translate file.md --to fr` (explicit path) instead.

**Binary file detection:** Before processing, the tool checks whether each input file is binary by scanning the first 8 KB for null bytes or other non-text byte sequences. If a binary file is detected, it is skipped with an error: `"Error: '<filename>' appears to be a binary file and cannot be translated."` In multi-file mode, binary files are skipped and processing continues with the remaining files.

**File encoding:** All text files are assumed to be **UTF-8**. If a file contains invalid UTF-8 sequences, the tool errors: `"Error: '<filename>' contains invalid UTF-8. Please re-encode the file as UTF-8 before translating."` In multi-file mode, this is treated as a per-file failure (see Section 3.5).

**Empty file:** An empty file (zero bytes or only whitespace) produces a warning and is skipped: `"Warning: '<filename>' is empty. Skipping."` The file is not sent to the provider.

Output destinations:
- Single file (explicit path, not glob): **stdout** by default (redirectable with `--output` or `--in-place`).
- Multiple files, or a single file matched via glob: **new files alongside the originals** by default, using the `_{TO}` suffix naming convention (see Section 3.4).

### 2.3 Stdin (Pipe)

When no positional argument is given and stdin is not a TTY (i.e. data is being piped), the tool reads from stdin.

```
cat notes.txt | translate --to fr
echo "Hola mundo" | translate --to en
```

Output goes to **stdout**. Format defaults to `text` for stdin since there is no filename extension to infer from.

### 2.4 Ambiguity Resolution

If a positional argument is given and `--text` is not set:
- If it resolves to an existing file → file mode.
- If it does not resolve to an existing file → inline text mode.
- If multiple positional arguments are given and any does not resolve to an existing file → error: `"Argument '<arg>' is not a valid file path. To translate a literal string, use --text."`

**Empty inline text:** `translate "" --to fr` produces an error: `"Error: Input text is empty."` Empty stdin (zero bytes) produces the same error.

---

## 3. Output Modes

### 3.1 Stdout (Default for Single Explicit File or Inline Text)

When input is inline text, stdin, or a single file provided as an explicit path (not a glob), the translated result is printed to stdout with a trailing newline.

**Streaming:** When the output destination is stdout and the provider supports streaming, the tool streams the response as it arrives, providing a better interactive experience. When the output destination is a file (`--output`, `--in-place`, or multi-file / glob mode), the tool buffers the full response before writing to avoid leaving a partial file if the stream fails midway.

### 3.2 `--output <FILE>` (Single Explicit File or Inline Text / Stdin Only)

Writes the buffered result to the specified file path. If the file already exists, prompts for confirmation unless `--yes` is given.

```
translate document.md --to fr --output document_fr.md
```

**Conflict:** `--output` is not allowed when multiple input files are provided or when input is a glob pattern. Error: `"--output can only be used with a single input. Use --suffix to control output filenames for multiple files."`

### 3.3 `--in-place` (File Input Only)

Overwrites the original input file(s) with the translation. Requires confirmation unless `--yes` is passed.

Interactive confirmation prompt: `"This will overwrite 3 file(s). Proceed? [y/N]"`

**Non-TTY behavior:** If stdin is not a TTY and `--yes` has not been passed, the tool does not hang waiting for input. It aborts immediately with exit code 3: `"Error: Interactive confirmation required but stdin is not a TTY. Use --yes to confirm non-interactively."` This behavior applies to all interactive prompts in the tool.

**Conflicts:**
- `--in-place` + inline text or stdin → error: `"--in-place requires file input."`
- `--in-place` + `--output` → error: `"--in-place and --output cannot be used together."`
- `--in-place` + `--suffix` → error: `"--in-place and --suffix cannot be used together. --in-place overwrites the original file; --suffix creates a new file."`

### 3.4 Multi-file Output Naming

When multiple files are translated (or a single file via glob) and neither `--output` nor `--in-place` is used, each output file is written alongside the original using the following naming convention:

```
{stem}_{TO_UPPER}{ext}
```

The **extension** is defined as everything from the **last dot** in the filename to the end. For compound extensions, only the final segment is treated as the extension. If the filename has **no extension** (no dot), the suffix is appended directly to the end of the filename.

Examples:

| Input | `--to` | Output |
|---|---|---|
| `document.md` | `fr` | `document_FR.md` |
| `README.md` | `ja` | `README_JA.md` |
| `notes.txt` | `de` | `notes_DE.txt` |
| `index.html` | `zh` | `index_ZH.html` |
| `view.blade.php` | `fr` | `view.blade_FR.php` |
| `archive.tar.gz` | `es` | `archive.tar_ES.gz` |
| `Makefile` | `fr` | `Makefile_FR` |
| `README` | `ja` | `README_JA` |

The language code in the filename is always the **uppercase** ISO 639-1 code (e.g. `FR`, `JA`, `ZH`).

**Custom suffix:** Use `--suffix <SUFFIX>` to override the default naming. The suffix is inserted before the final extension (or appended to the end for extensionless files).

```
translate *.md --to fr --suffix .translated
# → file.translated.md
```

**`--suffix` with single explicit file (no glob):** `--suffix` has no effect when a single file is provided as an explicit path with no `--in-place` or `--output`, because the output goes to stdout. A warning is emitted: `"Warning: --suffix has no effect when outputting to stdout. Use --output to write to a file."` The flag is otherwise ignored.

**File already exists:** If the output file already exists, prompt for confirmation unless `--yes` is given: `"Output file 'document_FR.md' already exists. Overwrite? [y/N]"`. Non-TTY behavior as described in Section 3.3 applies.

### 3.5 Multi-file Partial Failure

When translating multiple files, the tool uses **continue-on-error** behavior: if one file fails (API error, encoding error, binary file, etc.), the tool logs the error to stderr, skips that file, and continues processing the remaining files.

At the end of a multi-file run, if any files failed, the tool prints a summary to stderr:

```
Translation complete: 4 succeeded, 1 failed.
Failed files:
  - notes.txt: API error: context length exceeded
```

If any files failed, the exit code is `1` even if other files succeeded. Successfully translated and written output files are kept — they are not cleaned up on failure.

---

## 4. Full Flag Reference

### Input / Output

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| *(positional)* | | `STRING\|FILE...` | | Input text or file path(s). Glob patterns are expanded by the tool. |
| `--text` | | flag | false | Force the positional argument to be treated as literal inline text, bypassing file detection. No short form to avoid confusion with `-t` (`--to`). |
| `--output` | `-o` | `FILE` | | Write output to file. Single explicit file or inline text/stdin only. |
| `--in-place` | `-i` | flag | false | Overwrite input file(s) with translation. File input only. |
| `--suffix` | | `STRING` | `_{TO}` | Custom output filename suffix (before the final extension). Multi-file or glob mode only. |
| `--yes` | `-y` | flag | false | Skip all confirmation prompts. |
| `--jobs` | `-j` | `INT` | `1` | Number of files to translate in parallel. Only meaningful for file input with multiple files. Ignored (with a warning) for inline text and stdin. |

### Languages

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--from` | `-f` | `LANG` | `auto` | Source language. Accepts full name, ISO 639-1 code, or BCP 47 tag. `auto` instructs the provider to detect the language. |
| `--to` | `-t` | `LANG` | `en` | Target language. Same format as `--from`. `auto` is not a valid value for `--to`. |

Language values are normalized internally. The following are all equivalent: `French`, `french`, `fr`, `fra`. If a value passed to `--from` or `--to` is not recognized as a valid language name, ISO 639-1 code, or BCP 47 tag (and is not `auto` for `--from`), the tool errors: `"Error: '<value>' is not a recognized language. Use a language name (e.g. 'French'), ISO 639-1 code (e.g. 'fr'), or BCP 47 tag (e.g. 'zh-TW')."`

### Provider

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--provider` | `-p` | `NAME` | `openai` (or from config) | Translation backend. See Section 7 for valid values. To use a named `openai-compatible` endpoint defined in the config, pass its name directly (e.g. `--provider lm-studio`). |
| `--model` | `-m` | `STRING` | *(provider default)* | Model ID. Not applicable for `apple-translate` or `deepl`. |
| `--base-url` | | `URL` | *(provider default)* | API base URL. Required for anonymous `openai-compatible` usage. |
| `--api-key` | | `STRING` | *(from env var)* | API key. Overrides environment variable. Intended for ephemeral or testing use. Prefer environment variables or the config file for regular use, as CLI values are visible in shell history and process listings (`ps aux`). |

### Prompts

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--preset` | | `NAME` | `general` | Named prompt preset. See Section 6. |
| `--system-prompt` | | `TEMPLATE\|@FILE` | *(from preset)* | Override the system prompt. Use `@path/to/file.txt` to load from a file. Supports all placeholders. |
| `--user-prompt` | | `TEMPLATE\|@FILE` | *(from preset)* | Override the user prompt. Supports all placeholders. |
| `--context` | `-c` | `STRING` | `""` | Additional context. Leading and trailing whitespace is trimmed. Available as `{context}` (raw value) and `{context_block}` (formatted, with prefix) in prompts. |
| `--no-lang` | | flag | false | Suppress the warning when `{from}` or `{to}` placeholders are absent from a custom prompt. Use this when languages are hardcoded in your prompt. |

### Format

| Flag | | Type | Default | Description |
|---|---|---|---|---|
| `--format` | | `FMT` | `auto` | Input format hint: `auto`, `text`, `markdown`, `html`. When `auto`, format is inferred from file extension. Has no effect for prompt-less providers (`apple-translate`, `deepl`). |

**`--format auto` detection rules:**

| Extension(s) | Detected Format | `{format}` resolves to |
|---|---|---|
| `.md`, `.markdown`, `.mdx` | markdown | `markdown` |
| `.html`, `.htm` | html | `HTML` |
| `.txt` | text | `text` |
| *(all others)* | text | `text` |
| *(stdin)* | text | `text` |

### Utility

| Flag | Short | Type | Default | Description |
|---|---|---|---|---|
| `--dry-run` | | flag | false | Print the fully resolved prompts and provider/model that would be used. Does not call any API. |
| `--verbose` | `-v` | flag | false | Print provider, model, detected language, token usage, elapsed time, and output filename(s) to stderr. |
| `--quiet` | `-q` | flag | false | Suppress all warnings. Errors are still printed to stderr. Mutually exclusive with `--verbose`. |
| `--config` | | `FILE` | `~/.config/translate/config.toml` | Path to config file. |
| `--help` | `-h` | flag | | Print help and exit. |
| `--version` | | flag | | Print version string and exit. |

---

## 5. Prompt Templating System

All prompts — both built-in and user-provided — are **templates**. Before a prompt is sent to a provider, the tool resolves all placeholders by substituting their values.

### 5.1 Available Placeholders

| Placeholder | Resolved From | Available In | Notes |
|---|---|---|---|
| `{from}` | `--from` flag | System prompt, User prompt | See §5.2 for `auto` resolution |
| `{to}` | `--to` flag | System prompt, User prompt | Full English display name, e.g. `French` |
| `{text}` | The input text | System prompt, User prompt | Available in both, though placing it in the system prompt is unusual. If present, it is resolved. |
| `{context}` | `--context` flag (raw, trimmed) | System prompt, User prompt | Empty string `""` when `--context` is not provided |
| `{context_block}` | `--context` flag (formatted) | System prompt, User prompt | Non-empty: `\nAdditional context: <value>`. Empty: `""`. Use in default prompts for clean conditional rendering. |
| `{filename}` | Source file basename | System prompt, User prompt | Empty string `""` when input is not a file |
| `{format}` | Detected or specified format | System prompt, User prompt | `text`, `markdown`, or `HTML` |

**Language normalization:** `{from}` and `{to}` always resolve to full English display names (e.g. `fr` → `French`, `zh-TW` → `Traditional Chinese`).

### 5.2 `{from}` Resolution When Source Language Is `auto`

When `--from auto` (the default), the source language is unknown at prompt-construction time. In this case, `{from}` resolves to the fixed phrase **`the source language`**. This produces naturally readable prompts:

> *"You are a skilled translator with expertise in translating the source language to French."*
> *"Translate the following markdown from the source language to French."*

This is correct behavior for LLM providers, which detect the source language from the input text. For prompt-less providers (`apple-translate`, `deepl`), `{from}` is irrelevant since no prompt is sent.

The string `"the source language"` should be defined as a named constant in the implementation so it can be changed in one place if needed.

### 5.3 `{context}` vs. `{context_block}`

Two context-related placeholders serve different use cases:

- **`{context}`** resolves to the raw, trimmed value of `--context`. If no context is given, it is an empty string. Use this when embedding the context value inline in a custom sentence: `"The context for this string is: {context}."`
- **`{context_block}`** resolves to a formatted block when non-empty: `\nAdditional context: <value>`. When empty, it resolves to an empty string. Use this when you want the context to appear as a natural add-on line — or not appear at all when absent.

The default prompt templates use `{context_block}`. Custom prompts can use either.

### 5.4 Providing Custom Prompts

A custom prompt can be provided as:

**An inline string:**
```
translate file.md --to fr --system-prompt "You are a formal legal translator. Translate from {from} to {to}."
```

**A file reference (prefix with `@`):**
```
translate file.md --to fr --system-prompt @~/prompts/legal_system.txt
```

The file is read at invocation time. Relative paths are resolved from the current working directory. If the file does not exist: `"Error: Prompt file '<path>' not found."`

### 5.5 Language Placeholder Warning

When a custom prompt is provided (via `--system-prompt` or `--user-prompt`) and **neither `{from}` nor `{to}` appear anywhere in either prompt**, the tool emits a warning to stderr:

```
Warning: Your custom prompt does not contain {from} or {to} placeholders.
         The tool cannot confirm that a target language is specified.
         If you have hardcoded languages in your prompt, pass --no-lang to suppress this warning.
```

This warning is suppressed by `--quiet` or `--no-lang`.

### 5.6 LLM Output Sanitization

LLM providers frequently wrap their response in a triple-backtick code fence despite being instructed not to. The tool automatically strips such wrapping when **all three** of the following are true:

1. The response begins with a triple-backtick line (optionally followed by a language tag, e.g. ` ```markdown `).
2. The response ends with a closing triple-backtick line.
3. The wrapping encompasses the **entire** response — there is no content outside the fences.

Only the outermost wrapping is stripped. Code blocks embedded within the translated content are preserved. When stripping occurs, it is logged in `--verbose` mode: `"Info: Stripped wrapping code fence from LLM response."`

### 5.7 `--dry-run` Output

When `--dry-run` is set, the tool prints to stdout and exits without calling any API:

```
=== DRY RUN ===

Provider:       anthropic
Model:          claude-3-5-haiku-latest
Source lang:    the source language (auto-detect)
Target lang:    French

--- SYSTEM PROMPT ---
(full resolved system prompt)

--- USER PROMPT ---
(full resolved user prompt, with {text} substituted)

--- INPUT (first 500 chars) ---
(input text, truncated with "..." if longer)
```

---

## 6. Presets

A preset is a **named bundle** that can specify any of: a system prompt template, a user prompt template, a provider, a model, a default `--from`, and a default `--to`. Presets allow users to define reusable translation profiles.

### 6.1 Built-in Presets

| Preset Name | Description |
|---|---|
| `general` | Default. General-purpose translation. Preserves formatting and tone. |
| `markdown` | Preserves all markdown structure. Does not translate URLs, anchor links, image sources, frontmatter keys, or code. |
| `xcode-strings` | For Xcode `.xcstrings` / string catalog UI text. Preserves format specifiers (`%@`, `%lld`, `%1$@`, etc.). |
| `legal` | Formal register. Strict fidelity to source meaning. No paraphrasing or simplification. |
| `ui` | Short strings: button labels, tooltips, menu items. Terse and context-aware. Pairs well with `--context`. |

See Section 13 for the full default prompt text for each preset.

### 6.2 User-Defined Presets

Users define custom presets in the config file under `[presets.<n>]`. Both inline prompts and file-based prompts are supported. If both `system_prompt` and `system_prompt_file` are specified for the same preset, the inline `system_prompt` takes precedence. The same rule applies to `user_prompt` vs. `user_prompt_file`.

```toml
[presets.my-company]
system_prompt    = "You are a translator for Acme Corp. Translate from {from} to {to}."
user_prompt_file = "~/.config/translate/prompts/company_user.txt"
provider         = "anthropic"
model            = "claude-3-5-haiku-latest"
from             = "auto"
to               = "en"

[presets.terse]
system_prompt = "Translate {from} to {to}. Be extremely concise."
```

All fields are optional. Unspecified fields fall back to the `general` built-in defaults. A preset with only `provider` set is valid.

**Shadowing built-ins:** A user-defined preset with the same name as a built-in (e.g. `[presets.general]`) takes precedence over the built-in.

### 6.3 Preset Resolution Order

When `--preset <n>` is given:
1. Look in the user's config file under `[presets.<n>]`.
2. Fall back to built-in presets.
3. If not found: `"Error: Unknown preset '<n>'. Run translate presets list to see available presets."`

### 6.4 Full Option Resolution Order

For every configurable option, precedence from highest to lowest is:

1. **CLI flags** (always win)
2. **Active preset values** (from `--preset` or the config default preset)
3. **Config `[defaults]`** values
4. **Built-in defaults**

Example: if the active preset sets `to = "en"` and config `[defaults]` sets `to = "fr"`, and the user does not pass `--to`, the preset value `"en"` wins.

### 6.5 Preset Field Override Rules

CLI flags override preset values on a per-field basis:

- `--system-prompt` on the CLI overrides the preset's system prompt.
- `--to de` overrides the preset's `to`.
- `--provider openai` overrides the preset's `provider`.

---

## 7. Providers

### 7.1 Provider List

| Provider Name | Description | Prompt Support | Model Support | API Key Required |
|---|---|---|---|---|
| `openai` | OpenAI API | Yes | Yes | Yes (`OPENAI_API_KEY`) |
| `anthropic` | Anthropic Claude API | Yes | Yes | Yes (`ANTHROPIC_API_KEY`) |
| `ollama` | Local Ollama instance | Yes | Yes | No |
| `openai-compatible` | Any OpenAI-compatible API (anonymous) | Yes | Yes | Optional |
| `<named-endpoint>` | Named `openai-compatible` entry from config | Yes | Yes | Optional |
| `apple-intelligence` | macOS Apple Intelligence (on-device AI) | Yes | No | No (macOS only) |
| `apple-translate` | macOS system Translate framework | No | No | No (macOS only) |
| `deepl` | DeepL API | No | No | Yes (`DEEPL_API_KEY`) |

### 7.2 Per-Provider Defaults

| Provider | Default Base URL | Default Model |
|---|---|---|
| `openai` | `https://api.openai.com` | `gpt-4o-mini` |
| `anthropic` | `https://api.anthropic.com` | `claude-3-5-haiku-latest` |
| `ollama` | `http://localhost:11434` | `llama3.2` |
| `openai-compatible` (anonymous) | *(required)* | *(required)* |
| `apple-intelligence` | n/a | n/a |
| `apple-translate` | n/a | n/a |
| `deepl` | `https://api.deepl.com` | n/a |

### 7.3 Providers Without Prompt Support (`apple-translate`, `deepl`)

These providers translate directly without any system or user prompt. When they are active:

- `--system-prompt`, `--user-prompt`, `--preset` (prompt portion only), `--context`, and `--format` are silently ignored with a warning to stderr (suppressed by `--quiet`).
- `--to` is **required**. If not provided and no config default is set: `"Error: --to is required when using <provider>. This provider does not use prompts and cannot infer a target language."`
- `--from` defaults to `auto`. Both providers natively support auto language detection.

Warning format for ignored flags:
```
Warning: --system-prompt is ignored when using apple-translate.
         This provider does not support custom prompts.
```

### 7.4 Named `openai-compatible` Endpoints

Named endpoints are defined in the config under `[providers.openai-compatible.<n>]` and invoked by passing their name to `--provider`.

**Resolution order for `--provider <name>`:**
1. Check built-in provider names first (`openai`, `anthropic`, `ollama`, `openai-compatible`, `apple-translate`, `apple-intelligence`, `deepl`).
2. Check named `openai-compatible` entries in the config file.
3. Error: `"Error: Unknown provider '<name>'. Run translate --help for valid providers."`

Built-in provider names always take precedence. This means that if a named endpoint in the config has the same name as a built-in provider, the built-in will always win. A warning is emitted at config-load time when such a collision is detected: `"Warning: Named endpoint '<name>' in config has the same name as a built-in provider and will never be used. Rename the endpoint to avoid this conflict."` This warning is emitted whenever the config is loaded, regardless of whether `--provider` is passed.

```
# Config:
[providers.openai-compatible.lm-studio]
base_url = "http://localhost:1234/v1"
model    = "phi-4"

# Invocation:
translate file.md --to fr --provider lm-studio
```

**Anonymous `openai-compatible`:** Using `--provider openai-compatible` directly (without a named config entry) requires both `--base-url` and `--model` to be provided on the CLI or via `[providers.openai-compatible]` (without a sub-name) in the config.

**Auto-inference from `--base-url`:** If `--base-url` is provided without an explicit `--provider` flag, the tool automatically sets the provider to `openai-compatible` and emits: `"Info: --base-url provided; provider set to openai-compatible."` (suppressed by `--quiet`). If `--base-url` is provided alongside an explicit `--provider` that is a built-in non-compatible provider (e.g. `--provider anthropic --base-url ...`), that is a hard error (see Section 11.1).

### 7.5 Apple Providers (macOS Only)

`apple-translate` and `apple-intelligence` are only available on macOS. Minimum OS requirements:

| Provider | Minimum macOS Version |
|---|---|
| `apple-translate` | macOS 14 (Sonoma) |
| `apple-intelligence` | macOS 15.1 (Sequoia) |

On a non-macOS system: `"Error: Provider '<name>' is only available on macOS."`

On an incompatible macOS version: `"Error: Provider '<name>' requires macOS <version> or later. Current version: <detected-version>."`

The version check happens at startup, before any translation attempt, to fail fast with a clear message.

### 7.6 Timeout and Retry Policy

The following defaults apply to all HTTP-based providers. All values are configurable in the config file under `[network]` (see Section 8.2).

| Setting | Default | Description |
|---|---|---|
| Request timeout | 120 seconds | Total time allowed per API request |
| Retries | 3 | Number of retry attempts for transient errors |
| Retryable status codes | 429, 500, 502, 503, 504 | Other codes are not retried |
| Retry strategy | Exponential backoff | Base delay: 1s. Max delay: 30s. Jitter: ±20% |

**Timeout error:** `"Error: Request timed out after 120s. Use 'translate config set network.timeout_seconds <value>' to increase the limit."`

**Context window / token limit errors:** If the provider returns a context length error (HTTP 400 with a context-length error body), the tool surfaces this without retrying: `"Error: Input exceeds the model's context window. Consider a model with a larger context window, or split the input into smaller files."` Chunking large files is out of scope for v1.

**Rate limit (429):** Retried with exponential backoff. The `Retry-After` response header is respected if present.

---

## 8. Configuration File

### 8.1 Location

Default path: `~/.config/translate/config.toml`

Override with `--config <FILE>` or the `TRANSLATE_CONFIG` environment variable.

If the file does not exist, all built-in defaults apply. The file and any necessary parent directories are created automatically when `translate config set` is first run. On Unix/macOS, the file is created with permissions `0600` (owner read/write only) to protect API keys.

### 8.2 Full Schema

```toml
# ~/.config/translate/config.toml

[defaults]
provider = "openai"          # Default provider (built-in name or named endpoint)
from     = "auto"            # Default source language
to       = "en"              # Default target language
preset   = "general"         # Default preset name
format   = "auto"            # Default format hint
yes      = false             # Skip confirmation prompts globally
jobs     = 1                 # Default parallelism for multi-file translation

[network]
timeout_seconds          = 120   # HTTP request timeout per request
retries                  = 3     # Number of retry attempts for transient errors
retry_base_delay_seconds = 1     # Exponential backoff base delay

[providers.openai]
api_key = "sk-..."           # Overrides OPENAI_API_KEY env var
model   = "gpt-4o-mini"

[providers.anthropic]
api_key = "sk-ant-..."
model   = "claude-3-5-haiku-latest"

[providers.ollama]
base_url = "http://localhost:11434"
model    = "llama3.2"

[providers.deepl]
api_key = "..."

# Anonymous openai-compatible (used with --provider openai-compatible)
[providers.openai-compatible]
base_url = "http://localhost:1234/v1"
model    = "phi-4"

# Named openai-compatible endpoints (invoked with --provider <name>)
[providers.openai-compatible.lm-studio]
base_url = "http://localhost:1234/v1"
model    = "phi-4"

[providers.openai-compatible.my-vps]
base_url = "https://llm.example.com/v1"
model    = "mistral"
api_key  = "..."

# User-defined presets
[presets.my-company]
system_prompt    = "You are a translator for Acme Corp. Translate from {from} to {to}."
user_prompt_file = "~/.config/translate/prompts/company_user.txt"
provider         = "anthropic"
model            = "claude-3-5-haiku-latest"
to               = "en"

[presets.quick-deepl]
provider = "deepl"
to       = "en"

[presets.terse]
system_prompt = "Translate {from} to {to}. Be extremely concise."

[presets.xcode-custom]           # Shadow the built-in xcode-strings preset
system_prompt_file = "~/work/prompts/my_xcode_system.txt"
# user_prompt not set → falls back to general built-in user prompt
```

### 8.3 Precedence

CLI flags → preset values → config `[defaults]` → built-in defaults (highest to lowest priority).

---

## 9. The `config` Sub-command

```
translate config <action> [KEY] [VALUE]
```

| Command | Description |
|---|---|
| `translate config show` | Print the current effective configuration (file values merged with built-in defaults) in TOML format. |
| `translate config path` | Print the resolved config file path. |
| `translate config set <key> <value>` | Set a config value. Creates the file and parent directories if they don't exist. |
| `translate config get <key>` | Print the current value of a config key. |
| `translate config unset <key>` | Remove a key from the config file, restoring it to its built-in default. |
| `translate config edit` | Open the config file in `$EDITOR`. Falls back to `vi` on Unix/macOS, `notepad` on Windows if `$EDITOR` is not set. |

### Key Format

Keys use dot notation:

```
translate config set defaults.provider anthropic
translate config set defaults.to fr
translate config set providers.anthropic.model claude-opus-4-5
translate config set providers.ollama.base_url http://192.168.1.10:11434
translate config set network.timeout_seconds 60
translate config get defaults.provider
translate config unset providers.openai.api_key
```

---

## 10. The `presets` Sub-command

```
translate presets <action> [NAME]
```

| Command | Description |
|---|---|
| `translate presets list` | List all available presets (built-in and user-defined). Marks the active default with `*`. Indicates whether each is built-in or user-defined. |
| `translate presets show <name>` | Print the raw system and user prompt templates for the named preset, with placeholders **intact** (not substituted with example values). This is useful for copying and customizing a built-in prompt. |
| `translate presets which` | Print the name and source of the preset that would be active given current flags and config. |

**`presets show` displays raw templates**, not resolved prompts. The output will contain placeholders like `{from}`, `{to}`, and `{text}` as literal text, making it suitable for copying into a custom prompt file.

Example output of `translate presets list`:

```
BUILT-IN PRESETS
  general        *  General-purpose translation
  markdown          Preserves markdown formatting
  xcode-strings     Xcode string catalogs with format specifiers
  legal             Formal, strict fidelity
  ui                Short UI strings, button labels

USER-DEFINED PRESETS (in ~/.config/translate/config.toml)
  my-company        Custom company translation profile
  quick-deepl       Pinned to DeepL provider
  terse             Extremely concise output

  * = active default
```

---

## 11. Validation Rules and Error Handling

### 11.1 Hard Errors (Stop Execution)

| Condition | Error Message |
|---|---|
| `--output` + multiple files or glob input | `"--output can only be used with a single input. Use --suffix for multiple files."` |
| `--in-place` + inline text or stdin | `"--in-place requires file input."` |
| `--in-place` + `--output` | `"--in-place and --output cannot be used together."` |
| `--in-place` + `--suffix` | `"--in-place and --suffix cannot be used together. --in-place overwrites the original file; --suffix creates a new file."` |
| `--model` + `apple-translate` or `deepl` | `"--model is not applicable for <provider>. This provider does not use a model."` |
| `--api-key` + `apple-translate` or `apple-intelligence` | `"--api-key is not applicable for <provider>."` |
| `--base-url` given alongside an explicit non-`openai-compatible` built-in `--provider` | `"--base-url cannot be used with --provider <name>. It is only valid for openai-compatible providers."` |
| `openai-compatible` (anonymous) without `--base-url` and no config value | `"--base-url is required when using openai-compatible."` |
| `openai-compatible` (anonymous) without `--model` and no config value | `"--model is required when using openai-compatible."` |
| `apple-translate` or `deepl` without `--to` and no config default | `"--to is required when using <provider>. This provider does not use prompts and cannot infer a target language."` |
| `--to auto` | `"'auto' is not valid for --to. A specific target language is required. Example: --to fr"` |
| Invalid value for `--from` or `--to` (not a recognized language, code, or `auto` for `--from`) | `"'<value>' is not a recognized language. Use a language name (e.g. 'French'), ISO 639-1 code (e.g. 'fr'), or BCP 47 tag (e.g. 'zh-TW')."` |
| Apple provider on non-macOS | `"Provider '<name>' is only available on macOS."` |
| Apple provider on incompatible macOS version | `"Provider '<name>' requires macOS <version> or later. Current version: <detected-version>."` |
| Unknown preset name | `"Unknown preset '<name>'. Run translate presets list to see available presets."` |
| Unknown provider name | `"Unknown provider '<name>'. Run translate --help for valid providers."` |
| Input file not found | `"Input file '<path>' not found."` |
| `@FILE` prompt reference not found | `"Prompt file '<path>' not found."` |
| Glob pattern matches zero files | `"No files matched the pattern '<pattern>'."` |
| Input is a binary file (single file mode) | `"'<filename>' appears to be a binary file and cannot be translated."` |
| Input file contains invalid UTF-8 (single file mode) | `"'<filename>' contains invalid UTF-8. Please re-encode the file as UTF-8 before translating."` |
| Empty inline text or empty stdin | `"Error: Input text is empty."` |
| `--verbose` and `--quiet` both set | `"--verbose and --quiet cannot be used together."` |
| API call fails (non-retryable) | Provider error message + HTTP status if available. Exit code 1. |
| Request timeout | `"Error: Request timed out after <N>s. Use 'translate config set network.timeout_seconds <value>' to increase the limit."` |
| Context window exceeded | `"Error: Input exceeds the model's context window. Consider a model with a larger context window, or split the input into smaller files."` |
| Interactive confirmation needed in non-TTY | `"Error: Interactive confirmation required but stdin is not a TTY. Use --yes to confirm non-interactively."` Exit code 3. |

### 11.2 Warnings (Print to Stderr, Suppressed by `--quiet`)

| Condition | Warning |
|---|---|
| Custom prompt provided without `{from}` or `{to}` placeholders, and `--no-lang` not set | `"Warning: Your custom prompt does not contain {from} or {to} placeholders. If you have hardcoded languages, pass --no-lang to suppress this warning."` |
| `--no-lang` used with default prompts (no custom prompt active) | `"Warning: --no-lang has no effect when using default prompts."` |
| `--system-prompt`, `--user-prompt`, `--context`, `--format`, or `--preset` used with `apple-translate` or `deepl` | `"Warning: --<flag> is ignored when using <provider>. This provider does not support custom prompts."` |
| `--base-url` provided without explicit `--provider`, so provider is auto-set | `"Info: --base-url provided; provider set to openai-compatible."` |
| Named endpoint in config has same name as a built-in provider | `"Warning: Named endpoint '<name>' in config has the same name as a built-in provider and will never be used. Rename the endpoint to avoid this conflict."` (emitted at config-load time) |
| `--jobs` used with non-file input (inline text or stdin) | `"Warning: --jobs has no effect for non-file input."` |
| `--suffix` used with a single explicit file (no glob) going to stdout | `"Warning: --suffix has no effect when outputting to stdout. Use --output to write to a file."` |
| Input file is empty | `"Warning: '<filename>' is empty. Skipping."` |
| LLM response had wrapping code fence that was stripped | Logged only in `--verbose` mode: `"Info: Stripped wrapping code fence from LLM response."` |

---

## 12. Behavior by Scenario

| Command | Behavior |
|---|---|
| `translate "Bonjour" --to en` | Inline text → stdout |
| `translate "Bonjour"` | Inline text → stdout, `--to` defaults to `en` |
| `translate --text document.md --to en` | Translates the literal string `"document.md"`, not the file |
| `translate file.md --to fr` | Single explicit file → stdout |
| `translate "*.md" --to fr` | Glob (1 match) → `file_FR.md` (always file output mode for globs) |
| `translate file.md --to fr -o out.md` | Single file → written to `out.md` |
| `translate file.md --to fr -i` | Prompts confirmation (TTY only), then overwrites in place |
| `translate file.md --to fr -i -y` | Overwrites in place, no prompt |
| `translate file.md --to fr -i` *(in CI, non-TTY)* | Aborts with exit code 3 |
| `translate *.md --to fr` | Multiple files → `file_FR.md` alongside each original |
| `translate *.md --to fr --suffix .fr` | Multiple files → `file.fr.md` alongside each original |
| `translate *.md --to fr --jobs 4` | Multiple files translated 4 at a time |
| `cat file.txt \| translate --to fr` | Stdin → stdout |
| `translate file.md --provider apple-translate --to zh` | Apple Translate (no prompts used) |
| `translate file.md --provider deepl --to es` | DeepL (no prompts used) |
| `translate file.md --provider lm-studio --to fr` | Named openai-compatible endpoint from config |
| `translate file.md --to de --system-prompt "Translate {from} to {to}. Be terse."` | Custom inline system prompt |
| `translate file.md --to de --system-prompt @my_prompt.txt --no-lang` | Prompt from file, language warning suppressed |
| `translate file.md --preset xcode-strings --to ja` | Built-in xcode-strings preset |
| `translate file.md --preset my-company` | User-defined preset from config |
| `translate file.md --to fr --dry-run` | Prints resolved prompts and provider, no API call |
| `translate file.md --to fr --verbose` | Translates and prints metadata (provider, model, tokens, timing) to stderr |
| `translate file.md --to fr --quiet` | Translates, suppresses warnings |
| `translate file.md --to fr --context "This is a tooltip"` | Context injected via `{context_block}` in user prompt |

---

## 13. Default Prompts

The following are the built-in prompt templates for each preset. All placeholders are resolved at runtime. Templates use `{context_block}` so context appears cleanly when provided and is absent otherwise.

When `--from auto` (the default), `{from}` resolves to `the source language`.

**Input delimiters:** The default user prompt templates use `<source_text>` XML tags to wrap `{text}`. This prevents delimiter collision when the input contains triple-backtick code blocks (e.g. when translating markdown files with code examples).

### 13.1 `general` Preset

**System Prompt:**
```
You are a skilled translator with expertise in translating {from} to {to}, preserving the original meaning, tone, and nuance.
Maintain any formatting present in the source text.
Only output the translation. Do not include explanations, commentary, or original text.
Do not wrap your output in backticks or code blocks.
```

**User Prompt:**
```
Translate the following {format} from {from} to {to}.{context_block}

<source_text>
{text}
</source_text>
```

---

### 13.2 `markdown` Preset

**System Prompt:**
```
You are a skilled translator with extensive experience in translating {from} text to {to} while maintaining all markdown formatting.
Preserve heading levels (e.g. # for H1, ## for H2), bullet points, numbered lists, bold (**text**), italics (*text*), inline code (`code`), code blocks, links, and line breaks exactly as in the source.
Do not translate URLs, href destinations, anchor link targets, image src values, code content, frontmatter keys, or other technical identifiers.
Do not wrap your output in backticks or a code block.
```

**User Prompt:**
```
Translate the following markdown from {from} to {to}.{context_block}

<source_text>
{text}
</source_text>
```

---

### 13.3 `xcode-strings` Preset

**System Prompt:**
```
You are a skilled translator with extensive experience in translating {from} UI text to {to} for macOS and iOS applications.
The text was taken from an Xcode string catalog (.xcstrings).
Preserve all format specifiers such as %@, %lld, %.2f, %1$@, %2$@, %3$@, %1$lld, %2$lld and similar placeholders. Place them at the contextually appropriate position in the translated string.
If there is markdown formatting, keep it intact.
Preserve the meaning and tone appropriate for a macOS/iOS user interface.
If multiple valid translations exist, use the context provided to choose the most natural and idiomatic option for a native {to} speaker.
Only output the translation. Do not include explanations, original text, or wrapping backticks.
```

**User Prompt:**
```
Translate the following {from} UI string to {to}.{context_block}

<source_text>
{text}
</source_text>
```

---

### 13.4 `legal` Preset

**System Prompt:**
```
You are a professional legal translator with expertise in translating legal and formal documents from {from} to {to}.
Your translation must be faithful to the source: do not paraphrase, simplify, omit, or add content.
Preserve the formal register, legal terminology, and document structure.
Only output the translated text. Do not include explanations, commentary, or wrapping backticks.
```

**User Prompt:**
```
Translate the following legal text from {from} to {to}.{context_block}

<source_text>
{text}
</source_text>
```

---

### 13.5 `ui` Preset

**System Prompt:**
```
You are a translator specializing in software UI copy. Translate {from} text to {to}.
Output concise, natural translations appropriate for buttons, labels, menu items, tooltips, and other interface elements.
Use standard UI conventions and terminology for {to}-speaking users of macOS and iOS.
Only output the translated string. Do not include backticks, quotation marks, or explanation.
```

**User Prompt:**
```
Translate the following UI string from {from} to {to}.{context_block}

<source_text>
{text}
</source_text>
```

---

## 14. Environment Variables

| Variable | Description |
|---|---|
| `OPENAI_API_KEY` | API key for the `openai` provider |
| `ANTHROPIC_API_KEY` | API key for the `anthropic` provider |
| `DEEPL_API_KEY` | API key for the `deepl` provider |
| `TRANSLATE_CONFIG` | Path to config file (overrides default `~/.config/translate/config.toml`) |
| `EDITOR` | Editor used by `translate config edit`. Falls back to `vi` on Unix/macOS, `notepad` on Windows. |

**API key precedence:** CLI `--api-key` > config file `api_key` field > environment variable.

**Security note:** Storing API keys in environment variables or the config file is strongly preferred over `--api-key`, which is visible in shell history and process listings. The config file is created with `0600` permissions on Unix/macOS. Users should avoid making it world-readable.

---

## 15. Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success — all inputs translated successfully |
| `1` | One or more errors occurred (API failure, file not found, encoding error, partial failure in multi-file mode) |
| `2` | Invalid arguments or flag conflict |
| `3` | Aborted by user (declined a confirmation prompt) or aborted because a confirmation prompt was required in a non-TTY context |

---

## 16. Help Text

The following is the output of `translate --help`:

```
USAGE:
  translate [TEXT] [OPTIONS]
  translate [FILE...] [OPTIONS]
  echo "text" | translate [OPTIONS]
  translate <subcommand> [OPTIONS]

EXAMPLES:
  translate "Bonjour le monde" --to en
  translate document.md --to fr
  translate *.md --to ja
  translate document.md --to de --context "Button label in settings"
  translate document.md --provider apple-translate --to zh
  translate document.md --provider lm-studio --to fr
  cat notes.txt | translate --to de
  translate document.md --to fr --dry-run
  translate document.md --preset xcode-strings --to ja

INPUT:
      --text                Force positional argument to be treated as literal text,
                            bypassing file detection (useful when a string matches a filename)
  TEXT                      Inline text to translate (if not a valid file path)
  FILE...                   One or more files to translate. Glob patterns (*.md) are
                            expanded by the tool on all platforms.
                            Note: globs always write output files, even if only one file matches.
  stdin                     Piped input is read when no positional arg is given

OUTPUT:
  -o, --output <FILE>       Write output to file [single explicit file or inline/stdin only]
  -i, --in-place            Overwrite input file(s) in place [file input only]
      --suffix <SUFFIX>     Output filename suffix before the final extension
                            [default for multiple files/globs: _{TO}, e.g. document_FR.md]
  -y, --yes                 Skip all confirmation prompts
  -j, --jobs <N>            Files to translate in parallel [default: 1]

LANGUAGES:
  -f, --from <LANG>         Source language or "auto" [default: auto]
  -t, --to <LANG>           Target language [default: en]
                            Accepts: full names ("French"), ISO 639-1 ("fr"), BCP 47 ("zh-TW")
                            Note: "auto" is not valid for --to

PROVIDER:
  -p, --provider <name>     openai | anthropic | ollama | openai-compatible |
                            apple-intelligence | apple-translate | deepl |
                            <named-endpoint-from-config>
                            [default: openai, or value from config]
  -m, --model <ID>          Model ID [default: depends on provider]
      --base-url <URL>      API base URL [required for anonymous openai-compatible]
      --api-key <KEY>       API key [overrides env var; prefer env vars for security]

PROMPTS:
      --preset <name>       Named prompt preset [default: general]
                            Run: translate presets list
      --system-prompt <TEMPLATE|@FILE>
                            Override system prompt. Use @path/to/file for file input.
                            Placeholders: {from}, {to}, {text}, {context}, {context_block},
                                          {filename}, {format}
      --user-prompt <TEMPLATE|@FILE>
                            Override user prompt. Same placeholders as above.
  -c, --context <TEXT>      Additional context. Available as {context} (raw) and
                            {context_block} (formatted with prefix) in prompts.
      --no-lang             Suppress warning when {from}/{to} are absent from a custom prompt

FORMAT:
      --format <FMT>        auto | text | markdown | html [default: auto]
                            auto detects from file extension:
                              .md, .markdown, .mdx → markdown
                              .html, .htm          → html
                              all others, stdin    → text
                            No effect for apple-translate or deepl.

UTILITY:
      --dry-run             Print resolved prompts and provider/model. No API call.
  -v, --verbose             Print provider, model, token usage, and timing to stderr
  -q, --quiet               Suppress warnings (errors still shown)
      --config <FILE>       Config file [default: ~/.config/translate/config.toml]
  -h, --help                Show this help
      --version             Show version

SUBCOMMANDS:
  config                    Manage configuration
                            translate config show | path | set | get | unset | edit
  presets                   Manage and inspect presets
                            translate presets list | show <name> | which

ENVIRONMENT VARIABLES:
  OPENAI_API_KEY            API key for OpenAI
  ANTHROPIC_API_KEY         API key for Anthropic
  DEEPL_API_KEY             API key for DeepL
  TRANSLATE_CONFIG          Path to config file
  EDITOR                    Editor for `translate config edit`
```

---

## 17. Developer Notes

This section contains implementation guidance. It does not affect the user-facing specification.

**Provider abstraction:** Implement providers behind a clean interface or trait (depending on language). At minimum, the interface should expose: `translate(system_prompt: Option<String>, user_prompt: String, from: Language, to: Language) -> Result<String>`. This makes adding new providers straightforward and isolates provider-specific logic. Prompt-less providers (`apple-translate`, `deepl`) simply ignore the prompt parameters.

**Output sanitization:** Implement the LLM response stripping described in Section 5.6 as a shared post-processing step applied to all LLM providers, not per-provider. Any new LLM provider added later will automatically benefit from it.

**Non-TTY safety:** The two most common causes of a CLI tool hanging indefinitely in CI/CD pipelines are (a) waiting for an HTTP response with no timeout and (b) blocking on a `[y/N]` prompt with no TTY. Both are specified in this document. Implement both from the start.

**Glob expansion:** Use a glob library rather than relying on the shell. On Unix, the shell may already expand `*.md` before the tool receives arguments — this is harmless since expanding already-resolved paths is a no-op. On Windows (cmd.exe, PowerShell), the literal string `*.md` will be passed to the tool, so the tool must expand it itself. The tool should also detect whether a positional argument *looks like* a glob pattern (contains `*`, `?`, or `[`) in order to apply glob output mode even for single-match results.

**Parallelism (`--jobs`):** Use a bounded thread pool or async task pool when `--jobs > 1`. Parallel requests may hit provider rate limits faster; this is documented behavior and the responsibility of the user when increasing `--jobs`.

**Streaming:** Use the provider's streaming API when output is going to stdout, for a better interactive experience. Buffer the full response before writing when output is going to a file, to prevent partial writes on stream failure.

**Config file permissions:** Create the config file with `0600` permissions on Unix/macOS. This is a security measure since the file may contain API keys.

**`{from}` when auto:** When `--from auto`, `{from}` resolves to the string `"the source language"`. Define this as a named constant in one place so it can be changed consistently if needed.

**Apple provider version checks:** Check the OS version at startup when an Apple provider is selected. Fail fast with a clear version error before attempting to invoke any Apple APIs, rather than relying on the API call itself to fail with an opaque system error.

**Inline vs. file prompts in presets:** Both `system_prompt` (inline string) and `system_prompt_file` (file path) are valid in a preset config entry. If both are present, inline takes precedence. Apply the same rule to `user_prompt` vs. `user_prompt_file`. Validate at startup that any referenced prompt files actually exist, and error early rather than failing mid-translation.

**Named endpoint collision detection:** The collision warning for named endpoints (Section 7.4) should be emitted at config-load time on every invocation, not just when `--provider` happens to match. This way users discover the misconfiguration immediately even if they are not currently using that provider.

**Apple Translate formatting:** The macOS `Translation` framework (`translationTask`) operates on plain text or basic attributed strings. It does not preserve markdown formatting in the same way an LLM would. The developer should note that `apple-translate` may strip or alter formatting in markdown input. This is a known limitation of the platform API and outside the scope of this tool to fix; it should be mentioned in user-facing documentation when the `apple-translate` provider is documented.

**`presets show` output:** The command prints raw prompt templates with placeholders intact (e.g. `{from}`, `{to}`, `{text}` as literal strings). Do not substitute example values. The intent is to give users a copy-pasteable starting point for customization.
