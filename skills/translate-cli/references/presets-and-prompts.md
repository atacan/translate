# Presets and Prompts

## Built-in presets

- `general`: general-purpose translation
- `markdown`: preserve markdown structure and technical blocks
- `xcode-strings`: preserve `%@`, `%lld`, `%1$@`-style placeholders
- `legal`: formal and strict-fidelity translation
- `ui`: concise UI labels and interface copy

List and inspect:

```bash
translate presets list
translate presets show markdown
translate presets which
```

## Prompt placeholders

Templates support:

- `{from}`
- `{to}`
- `{text}`
- `{context}`
- `{context_block}`
- `{filename}`
- `{format}`
- `{string_key}`, `{comment}`, `{segment}` (catalog metadata, empty when unavailable)

Substitution scans the original template once. Literal placeholders in inserted source, context, filenames, or metadata stay intact. Double-braced literals such as `{{to}}` remain exactly as written; they are not unescaped.

Providers that use prompts require a non-empty, non-whitespace user template and `{text}` in at least one of the two templates. A `{text}` token in the system template satisfies the source requirement even when the user template has none. Promptless providers do not load or validate unused templates. `presets show` displays raw templates without requiring execution validity.

`{context_block}` becomes empty when context is blank; otherwise it is rendered as:

`Additional context: <trimmed-context>`

## Override prompts

Inline:

```bash
translate --text --to en \
  --system-prompt "You translate {from} to {to}." \
  --user-prompt "Translate {format}: {text}" \
  "Merhaba dunya"
```

From files:

```bash
translate --text --to en \
  --system-prompt @./prompts/system.txt \
  --user-prompt @./prompts/user.txt \
  "Merhaba dunya"
```

## Warning behavior

- If resolved prompt content differs from its built-in fallback and neither `{from}` nor `{to}` exists, a warning is shown.
- Pass `--no-lang` to suppress that warning when languages are intentionally hardcoded.
- Presets that change only metadata (provider, model, languages, format, description), and overrides identical to default templates, retain default-prompt behavior.
- `--no-lang` with default prompts warns that it has no effect.
- Unsupported identifier-shaped tokens (for example `{target_language}`) warn once per token and remain literal. Ordinary JSON/CSS braces, malformed braces, and double-braced literals do not warn.
- `--no-lang` does not bypass template validation or suppress unknown-token warnings.

CLI overrides take precedence for each prompt field independently. Within a preset, `system_prompt` takes precedence over `system_prompt_file`; `user_prompt` takes precedence over `user_prompt_file`. A field without an override retains its preset or built-in fallback.

## User-defined presets in TOML

```toml
[presets.release-notes]
system_prompt = "You are a technical translator from {from} to {to}."
user_prompt = "Translate this markdown from {from} to {to}.{context_block}\n\n{text}"
provider = "openai"
model = "gpt-4o-mini"
from = "auto"
to = "en"
format = "markdown"
```

Supported keys inside `[presets.<name>]`:

- `system_prompt`
- `system_prompt_file`
- `user_prompt`
- `user_prompt_file`
- `provider`
- `model`
- `from`
- `to`
- `format`
