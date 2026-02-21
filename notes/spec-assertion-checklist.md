# Spec Assertion Checklist

## Implemented checks
- `--verbose` and `--quiet` conflict -> invalid arguments exit code 2.
- `--to auto` rejected with explicit message.
- Glob with zero matches -> runtime error exit code 1.
- Non-TTY confirmation without `--yes` -> abort exit code 3.
- Custom prompt language-placeholder warning.
- `--suffix` warning for single explicit file routed to stdout.
- Dry-run output includes provider/model/source/target/system/user/input preview sections.

## Known deferred/incomplete
- Apple providers (`apple-intelligence`, `apple-translate`) implementation.
- DeepL provider integration (deferred by milestone scope).
- `.xcstrings` workflow integration with `StringCatalogKit`.
