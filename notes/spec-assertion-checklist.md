# Spec Assertion Checklist

## Implemented checks
- `--verbose` and `--quiet` conflict -> invalid arguments exit code 2.
- `--to auto` rejected with explicit message.
- Glob with zero matches -> runtime error exit code 1.
- Non-TTY confirmation without `--yes` -> abort exit code 3.
- Custom prompt language-placeholder warning.
- `--suffix` warning for single explicit file routed to stdout.
- Dry-run output includes provider/model/source/target/system/user/input preview sections.
- HTTP retry policy retries only `429, 500, 502, 503, 504`.
- `Retry-After` header is respected with case-insensitive lookup.
- Apple provider flag applicability checks:
  - `apple-translate`: rejects `--model`, `--api-key`, and `--base-url`.
  - `apple-intelligence`: rejects `--api-key` and `--model`.
- DeepL provider checks:
  - rejects `--model` and `--base-url`.
  - enforces API key precedence (`--api-key` > config > `DEEPL_API_KEY`) and runtime requirement.
  - prompt-less translation path and retry handling are covered by unit tests.
- `.xcstrings` translation path routes through `StringCatalogKit` workflow.
- Catalog workflow maps `--jobs` to max concurrent catalog translation requests.
- Catalog workflow preserves partial-failure behavior and file-level summaries.
