# Validate custom prompt pairs

An empty user template is rejected even when system contains source text. A nonempty pair without {text} is rejected. Source text only in system is valid when user is nonempty. A hardcoded-language custom pair is valid but warns unless --no-lang is set.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/25-invalid-prompts
```

Files:

- `config.toml` — deliberately empty config.

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

Errors exit before dry-run message rendering. Dry-run does not contact a provider or validate a provider response.

## Command 1: Empty user rejected; no provider request.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --system-prompt 'Translate {from} to {to}: {text}' --user-prompt '' --text 'Hello world'
```

Expected exit status: `2`.

Expected stdout: empty; no messages are rendered.

Expected stderr:

```text
User prompt must not be empty. Provide a non-empty --user-prompt or preset user_prompt template.
```

## Command 2: No {text} rejected; no provider request.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --system-prompt 'Translate {from} to {to}.' --user-prompt 'Please translate.' --text 'Hello world'
```

Expected exit status: `2`.

Expected stdout: empty; no messages are rendered.

Expected stderr:

```text
Prompt templates must contain {text} in the system or user prompt so the source text is sent. Add {text} to --system-prompt, --user-prompt, or the preset templates.
```

## Command 3: Source in system is valid.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --system-prompt 'Translate {from} to {to}: {text}' --user-prompt 'Return only the translation.' --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: general
System prompt origin: CLI inline
User prompt origin: CLI inline
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
Translate English to French: Hello world

--- USER PROMPT ---
Return only the translation.

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

## Command 4: Hardcoded-language warning.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --system-prompt 'Translate English to French.' --user-prompt '{text}' --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: general
System prompt origin: CLI inline
User prompt origin: CLI inline
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
Translate English to French.

--- USER PROMPT ---
Hello world

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr:

```text
Warning: Your custom prompt does not contain {from} or {to} placeholders. If you have hardcoded languages, pass --no-lang to suppress this warning.
```

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
