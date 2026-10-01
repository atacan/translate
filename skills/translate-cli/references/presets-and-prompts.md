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

`presets list` marks locally overridden built-ins. `presets show` reports each field's effective origin and raw template. `presets which` reports the configured/text default without input inspection; catalogs can have the implicit `xcode-strings` default. Dry-run includes origins after CLI overrides.

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

CLI overrides take precedence for each prompt field independently. Within a preset, `system_prompt` takes precedence over `system_prompt_file`; `user_prompt` takes precedence over `user_prompt_file`. Missing fields of a same-named built-in preset fall back to that built-in; other custom names fall back to original built-in `general`, even if config customizes `general`. Relative TOML preset `*_prompt_file` paths resolve beside the containing config; CLI `@file` paths resolve from invocation cwd. Absolute and `~/` paths retain their semantics. Inactive or overridden files are never read.

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

- `description` (optional inspection text)
- `system_prompt`
- `system_prompt_file`
- `user_prompt`
- `user_prompt_file`
- `provider`
- `model`
- `from`
- `to`
- `format`

## Catalog resolution

Catalog requests use these templates per segment. `xcode-strings` is implicit only when no CLI preset, explicit config `defaults.preset`, or customized default/general preset selects another preset; explicit `general` wins. Mixed batches resolve defaults and provider/model/target metadata per route. CLI overrides apply independently to the matching prompt field for both routes. User fields fall back to the matching built-in preset, or built-in `general` for custom names.

Catalog `{context}` combines trimmed CLI context and developer comment on separate lines labeled `CLI context:` and `Developer comment:`. `{comment}` remains directly available. `{filename}` is the catalog basename, `{string_key}` is its entry key, and `{segment}` is `stringUnit`, `stringSet[index]`, or `variation[path]`. Catalog `sourceLanguage` determines `{from}` and provider source metadata; conflicting source settings warn. A format hint affects `{format}` only.

## Worked examples

Each walkthrough includes its files, command, exact rendered prompts, and an explanation of which fields win.

- CLI overrides: [inline prompts](https://github.com/atacan/translate/tree/main/examples/10-cli-inline-prompts), [prompt files](https://github.com/atacan/translate/tree/main/examples/11-cli-file-prompts), [system only](https://github.com/atacan/translate/tree/main/examples/12-cli-system-only), [user only](https://github.com/atacan/translate/tree/main/examples/13-cli-user-only), and [CLI files versus config files](https://github.com/atacan/translate/tree/main/examples/14-cli-file-over-config-file).
- Preset fallback: [partial built-in override](https://github.com/atacan/translate/tree/main/examples/07-partial-builtin-override) and [partial custom preset](https://github.com/atacan/translate/tree/main/examples/08-partial-custom-preset).
- Catalog preset selection: [implicit default](https://github.com/atacan/translate/tree/main/examples/17-catalog-defaults), [explicit general](https://github.com/atacan/translate/tree/main/examples/18-catalog-explicit-general), [customized general](https://github.com/atacan/translate/tree/main/examples/19-catalog-customized-general), [customized xcode-strings](https://github.com/atacan/translate/tree/main/examples/20-catalog-customized-xcode), and [metadata-only customization](https://github.com/atacan/translate/tree/main/examples/22-catalog-metadata-only-preset).
- Catalog request content: [CLI overrides, metadata, and combined context](https://github.com/atacan/translate/tree/main/examples/21-catalog-overrides-and-context).
