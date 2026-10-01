# Select a built-in preset

CLI `--preset markdown` wins over the text default. Both fields come from built-in `markdown`.

Run from the repository root after the [common setup](../README.md):

```sh
cd examples/02-builtin-preset
```

Files:

- `config.toml` — deliberately empty config.

Every command below is a dry run: no API calls, credentials, translation writes, or confirmations. Provider/model are pinned by CLI except where this case explicitly demonstrates preset metadata or a promptless provider. Languages are pinned by CLI; catalogs always take source from sourceLanguage.

## Command 1: Explicit markdown.

```sh
translate --dry-run --provider openai --model gpt-4o-mini --from en --to fr --config config.toml --preset markdown --text 'Hello world'
```

Expected exit status: `0`.

Expected stdout (complete rendered system/user messages for every shown request):

```text
Preset: markdown
System prompt origin: built-in preset markdown
User prompt origin: built-in preset markdown
=== DRY RUN ===

Provider:       openai
Model:          gpt-4o-mini
Source lang:    English
Target lang:    French

--- SYSTEM PROMPT ---
You are a skilled translator with extensive experience in translating English text to French while maintaining all markdown formatting.
Preserve heading levels (e.g. # for H1, ## for H2), bullet points, numbered lists, bold (**text**), italics (*text*), inline code (`code`), code blocks, links, and line breaks exactly as in the source.
Do not translate URLs, href destinations, anchor link targets, image src values, code content, frontmatter keys, or other technical identifiers.
Do not wrap your output in backticks or a code block.

--- USER PROMPT ---
Translate the following markdown from English to French.

<source_text>
Hello world
</source_text>

--- INPUT (first 500 chars) ---
Hello world
```

Expected stderr: empty.

The origin lines above identify the winning value for each prompt field. `<example-directory>` stands for this directory’s absolute path on your machine; all other message content and blank lines are literal. See the [common notes](../README.md) for output and live execution behavior.
