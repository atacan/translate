# Quickstart

## Translate inline text

```bash
translate --text --from tr --to en "Merhaba dunya"
```

## Auto-detect source language

```bash
translate --text --to fr "Hello world"
```

## Translate from stdin

```bash
echo "Merhaba dunya" | translate --to en
```

## Translate one file to stdout

```bash
translate --to de docs/input.md
```

## Translate one file to a destination file

```bash
translate --to de docs/input.md --output docs/input.de.md
```

## Overwrite a file in place

```bash
translate --to de docs/input.md --in-place --yes
```

## Translate many files with per-file outputs

```bash
translate --to fr docs/*.md --suffix _fr --jobs 4
```

## Force tool-side glob expansion

```bash
translate --to fr "docs/**/*.md"
```

## Use a preset

```bash
translate --preset markdown --to fr README.md
```

## Use custom prompt templates from files

```bash
translate --text --to en \
  --system-prompt @./prompts/system.txt \
  --user-prompt @./prompts/user.txt \
  "Merhaba dunya"
```

## Use a named openai-compatible endpoint from config

```bash
translate --provider lmstudio --to en "Merhaba dunya"
```

## Dry run before sending any request

```bash
translate --provider ollama --text --to en --dry-run "Merhaba dunya"
```

## Translate Xcode string catalogs

```bash
translate --preset xcode-strings --to fr Localizable.xcstrings
```

## Configure defaults once

```bash
translate config set defaults.provider anthropic
translate config set defaults.to fr
translate config set defaults.jobs 4
```
