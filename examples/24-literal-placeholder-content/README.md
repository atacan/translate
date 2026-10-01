# Substitute placeholders once

Templates substitute supported tokens once. Placeholder-shaped text introduced by source or context is preserved literally. JSON objects, CSS braces, and double braces are not template tokens. Repeated unsupported {mystery} produces one warning and remains literal in both messages.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/24-literal-placeholder-content
```

Files:

- `config.toml`
- `source.txt`

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Single-pass literal content.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset demo --context 'Literal {to}, {text}, and {{context}}.' source.txt
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
File: <example-directory>/source.txt
Mode: text translation
Preset: demo
System prompt origin: user preset demo inline
User prompt origin: user preset demo inline
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
Translate English to French. JSON {"ok": true}; CSS body { color: blue; }; {{to}}; {mystery}.

--- USER PROMPT ---
Keep {to} and {text} literal; JSON {"color": "blue"}; CSS body { color: blue; }; {{text}}.

Context: Literal {to}, {text}, and {{context}}.
Unsupported: {mystery}; double: {{text}}.

--- INPUT (first 500 chars) ---
Keep {to} and {text} literal; JSON {"color": "blue"}; CSS body { color: blue; }; {{text}}.

```

Expected stderr:

```text
Warning: Unsupported prompt placeholder {mystery} will be preserved literally. Use a supported placeholder or remove it from the template.
```

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
