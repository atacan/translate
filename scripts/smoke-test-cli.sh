#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH_DEFAULT="$ROOT_DIR/.build/arm64-apple-macosx/debug/translate"
if [[ -x "$BIN_PATH_DEFAULT" ]]; then
  CLI_CMD_DEFAULT="$BIN_PATH_DEFAULT"
else
  CLI_CMD_DEFAULT="swift run translate"
fi
CLI_CMD="${CLI_CMD:-$CLI_CMD_DEFAULT}"

RUN_LIVE=0
RUN_APPLE=0
KEEP_LOGS=0
VERBOSE=0

usage() {
  cat <<'EOF'
Usage: scripts/smoke-test-cli.sh [options]

Options:
  --live         Run optional live provider calls (requires provider availability/credentials)
  --apple        Run Apple provider dry-run tests (may fail on unsupported macOS versions)
  --cli <cmd>    Override CLI command (default: built binary if present, else "swift run translate")
  --keep-logs    Keep temp directory with logs/fixtures after completion
  --verbose      Print command output for passing tests too
  -h, --help     Show this help

Environment:
  CLI_CMD        Alternative way to override the CLI command
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) RUN_LIVE=1 ;;
    --apple) RUN_APPLE=1 ;;
    --keep-logs) KEEP_LOGS=1 ;;
    --verbose) VERBOSE=1 ;;
    --cli)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --cli" >&2; exit 2; }
      CLI_CMD="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/translate-smoke.XXXXXX")"
FIXTURES_DIR="$TMP_DIR/fixtures"
LOG_DIR="$TMP_DIR/logs"
mkdir -p "$FIXTURES_DIR/prompts" "$LOG_DIR"

cleanup() {
  if [[ "$KEEP_LOGS" -eq 1 ]]; then
    echo "Keeping temp files: $TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

create_fixtures() {
  printf 'Hello world\n' > "$FIXTURES_DIR/plain.txt"
  printf '# Hello\n\nThis is **bold**.\n' > "$FIXTURES_DIR/doc.md"
  printf '## Hello MDX\n\n<Button>Click me</Button>\n' > "$FIXTURES_DIR/doc.mdx"
  printf '<html><body><h1>Hello</h1><p>World</p></body></html>\n' > "$FIXTURES_DIR/page.html"
  printf '<p>Hello from htm</p>\n' > "$FIXTURES_DIR/page.htm"
  printf 'Hello from markdown extension\n' > "$FIXTURES_DIR/notes.markdown"
  printf 'A file named hello\n' > "$FIXTURES_DIR/hello"

  cat > "$FIXTURES_DIR/Localizable.xcstrings" <<'EOF'
{
  "sourceLanguage" : "en",
  "strings" : {
    "greeting" : {
      "comment" : "Greeting",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "needs_review",
            "value" : "Hello"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
EOF

  printf 'You are a translator from {from} to {to}. Only return translation.\n' > "$FIXTURES_DIR/prompts/system.txt"
  printf 'Translate this {format}:\n{text}\n' > "$FIXTURES_DIR/prompts/user.txt"

  cat > "$FIXTURES_DIR/test-config.toml" <<'EOF'
[defaults]
provider = "openai"
from = "auto"
to = "en"
preset = "general"
format = "auto"
yes = false
jobs = 1

[providers.openai-compatible.lmstudio]
base_url = "http://localhost:1234/v1"
model = "llama3.1"
api_key = ""
EOF
}

PASS_SUCCESS=0
FAIL_SUCCESS=0
PASS_FAILURE=0
FAIL_FAILURE=0
SKIP_COUNT=0
CASE_INDEX=0

print_section() {
  local title="$1"
  echo
  echo "== $title =="
}

run_snippet() {
  local label="$1"
  local expect="$2" # success|failure
  local snippet="$3"
  local logfile="$LOG_DIR/$(printf '%03d' "$CASE_INDEX")-$(echo "$label" | tr ' /:' '___' | tr -cd '[:alnum:]_.-').log"
  CASE_INDEX=$((CASE_INDEX + 1))

  (
    cd "$ROOT_DIR" || exit 99
    export FIXTURES_DIR
    export CLI_CMD
    bash -lc "set -o pipefail; $snippet"
  ) >"$logfile" 2>&1
  local status=$?

  local ok=1
  if [[ "$expect" == "success" && $status -eq 0 ]]; then
    ok=0
  elif [[ "$expect" == "failure" && $status -ne 0 ]]; then
    ok=0
  fi

  if [[ $ok -eq 0 ]]; then
    if [[ "$expect" == "success" ]]; then
      PASS_SUCCESS=$((PASS_SUCCESS + 1))
      printf '[PASS] %s\n' "$label"
    else
      PASS_FAILURE=$((PASS_FAILURE + 1))
      printf '[PASS expected-failure] %s (exit=%d)\n' "$label" "$status"
    fi
    if [[ "$VERBOSE" -eq 1 ]]; then
      sed 's/^/  | /' "$logfile"
    fi
    return 0
  fi

  if [[ "$expect" == "success" ]]; then
    FAIL_SUCCESS=$((FAIL_SUCCESS + 1))
    printf '[FAIL] %s (exit=%d)\n' "$label" "$status"
  else
    FAIL_FAILURE=$((FAIL_FAILURE + 1))
    printf '[FAIL expected-failure] %s (unexpected exit=%d)\n' "$label" "$status"
  fi
  sed 's/^/  | /' "$logfile"
  return 1
}

run_success() { run_snippet "$1" success "$2"; }
run_failure() { run_snippet "$1" failure "$2"; }

skip_case() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf '[SKIP] %s\n' "$1"
}

create_fixtures

print_section "Smoke Test Setup"
echo "Repo: $ROOT_DIR"
echo "CLI_CMD: $CLI_CMD"
echo "Fixtures: $FIXTURES_DIR"
echo "Logs: $LOG_DIR"

print_section "Expected Success: Core CLI and Subcommands"
run_success "help" '$CLI_CMD --help'
run_success "version" '$CLI_CMD --version'
run_success "config path default" '$CLI_CMD config path'
run_success "config path custom" '$CLI_CMD config path --config "$FIXTURES_DIR/test-config.toml"'
run_success "presets list" '$CLI_CMD presets list --config "$FIXTURES_DIR/test-config.toml"'
run_success "presets which" '$CLI_CMD presets which --config "$FIXTURES_DIR/test-config.toml"'
run_success "presets show general" '$CLI_CMD presets show general --config "$FIXTURES_DIR/test-config.toml"'
run_success "presets show markdown" '$CLI_CMD presets show markdown --config "$FIXTURES_DIR/test-config.toml"'
run_success "presets show xcode-strings" '$CLI_CMD presets show xcode-strings --config "$FIXTURES_DIR/test-config.toml"'

print_section "Expected Success: Config CRUD"
run_success "config show" '$CLI_CMD config show --config "$FIXTURES_DIR/test-config.toml"'
run_success "config get defaults.provider" '$CLI_CMD config get defaults.provider --config "$FIXTURES_DIR/test-config.toml"'
run_success "config set defaults.to" '$CLI_CMD config set defaults.to de --config "$FIXTURES_DIR/test-config.toml"'
run_success "config get defaults.to" '$CLI_CMD config get defaults.to --config "$FIXTURES_DIR/test-config.toml"'
run_success "config set defaults.jobs int" '$CLI_CMD config set defaults.jobs 4 --config "$FIXTURES_DIR/test-config.toml"'
run_success "config get defaults.jobs" '$CLI_CMD config get defaults.jobs --config "$FIXTURES_DIR/test-config.toml"'
run_success "config set named provider base_url" '$CLI_CMD config set providers.openai-compatible.local.base_url http://localhost:1234/v1 --config "$FIXTURES_DIR/test-config.toml"'
run_success "config set named provider model" '$CLI_CMD config set providers.openai-compatible.local.model llama3.1 --config "$FIXTURES_DIR/test-config.toml"'
run_success "config get named provider base_url" '$CLI_CMD config get providers.openai-compatible.local.base_url --config "$FIXTURES_DIR/test-config.toml"'
run_success "config unset defaults.jobs" '$CLI_CMD config unset defaults.jobs --config "$FIXTURES_DIR/test-config.toml"'
run_success "config edit non-interactive" 'EDITOR=true $CLI_CMD config edit --config "$FIXTURES_DIR/test-config.toml"'

print_section "Expected Success: Defaults and Input Modes"
# Important parser quirk for this CLI shape: keep options before positional input(s).
run_success "inline default dry-run" '$CLI_CMD --dry-run "Hello world"'
run_success "stdin default dry-run" 'printf "Hello via stdin\n" | $CLI_CMD --dry-run'
run_success "inline explicit en->de" '$CLI_CMD --text "Hello world" --from en --to de --dry-run'
run_success "auto->de" '$CLI_CMD --text "Hello world" --from auto --to de --dry-run'
run_success "to-only de" '$CLI_CMD --to de --dry-run "Hello world"'
run_success "force text" '$CLI_CMD --text --from en --to de --dry-run "hello"'
run_success "stdin explicit" 'printf "Hello stdin\n" | $CLI_CMD --from en --to de --dry-run'
run_success "single file dry-run" '$CLI_CMD --from en --to de --dry-run "$FIXTURES_DIR/plain.txt"'
run_success "multi file dry-run" '$CLI_CMD --from en --to de --dry-run "$FIXTURES_DIR/plain.txt" "$FIXTURES_DIR/doc.md"'
run_success "glob markdown dry-run" '$CLI_CMD --from en --to de --dry-run "$FIXTURES_DIR/*.md"'
run_success "glob html dry-run" '$CLI_CMD --from en --to de --dry-run "$FIXTURES_DIR/*.html"'

print_section "Expected Success: Format Coverage"
run_success "format auto txt" '$CLI_CMD --from en --to de --format auto --dry-run "$FIXTURES_DIR/plain.txt"'
run_success "format text txt" '$CLI_CMD --from en --to de --format text --dry-run "$FIXTURES_DIR/plain.txt"'
run_success "format auto md" '$CLI_CMD --from en --to de --format auto --dry-run "$FIXTURES_DIR/doc.md"'
run_success "format auto markdown ext" '$CLI_CMD --from en --to de --format auto --dry-run "$FIXTURES_DIR/notes.markdown"'
run_success "format auto mdx" '$CLI_CMD --from en --to de --format auto --dry-run "$FIXTURES_DIR/doc.mdx"'
run_success "format auto html" '$CLI_CMD --from en --to de --format auto --dry-run "$FIXTURES_DIR/page.html"'
run_success "format auto htm" '$CLI_CMD --from en --to de --format auto --dry-run "$FIXTURES_DIR/page.htm"'
run_success "format html override" '$CLI_CMD --from en --to de --format html --dry-run "$FIXTURES_DIR/page.html"'

print_section "Expected Success: Catalog (.xcstrings)"
run_success "xcstrings dry-run" '$CLI_CMD --from en --to de --dry-run "$FIXTURES_DIR/Localizable.xcstrings"'
run_success "xcstrings jobs dry-run" '$CLI_CMD --from en --to de --jobs 2 --dry-run "$FIXTURES_DIR/Localizable.xcstrings"'

print_section "Expected Success: Output Planning and Globals"
run_success "inline output file" '$CLI_CMD --text "Hello world" --from en --to de --output "$FIXTURES_DIR/out.txt" --dry-run'
run_success "stdin output file" 'printf "Hello stdin\n" | $CLI_CMD --from en --to de --output "$FIXTURES_DIR/stdin-out.txt" --dry-run'
run_success "single file explicit output" '$CLI_CMD --from en --to de --output "$FIXTURES_DIR/translated.txt" --dry-run "$FIXTURES_DIR/plain.txt"'
run_success "multi file suffix" '$CLI_CMD --from en --to de --suffix _DETEST --dry-run "$FIXTURES_DIR/plain.txt" "$FIXTURES_DIR/doc.md"'
run_success "glob suffix" '$CLI_CMD --from en --to de --suffix _GERMAN --dry-run "$FIXTURES_DIR/*.md"'
run_success "in-place yes" '$CLI_CMD --from en --to de --in-place --yes --dry-run "$FIXTURES_DIR/plain.txt"'
run_success "multi in-place yes jobs" '$CLI_CMD --from en --to de --in-place --yes --jobs 2 --dry-run "$FIXTURES_DIR/plain.txt" "$FIXTURES_DIR/doc.md"'
run_success "jobs inline warning path" '$CLI_CMD --text "Hello world" --from en --to de --jobs 3 --dry-run'
run_success "jobs stdin warning path" 'printf "Hello stdin\n" | $CLI_CMD --from en --to de --jobs 3 --dry-run'
run_success "verbose dry-run" '$CLI_CMD --text "Hello" --from en --to de --verbose --dry-run'
run_success "quiet dry-run" '$CLI_CMD --text "Hello" --from en --to de --quiet --dry-run'
run_success "config override dry-run" '$CLI_CMD --text "Hello" --from en --to de --config "$FIXTURES_DIR/test-config.toml" --dry-run'

print_section "Expected Success: Prompts and Presets"
run_success "preset ui" '$CLI_CMD --text "Save" --from en --to de --preset ui --dry-run'
run_success "preset markdown" '$CLI_CMD --from en --to de --preset markdown --dry-run "$FIXTURES_DIR/doc.md"'
run_success "preset xcode-strings" '$CLI_CMD --from en --to de --preset xcode-strings --dry-run "$FIXTURES_DIR/Localizable.xcstrings"'
run_success "preset legal" '$CLI_CMD --text "Terms and conditions" --from en --to de --preset legal --dry-run'
run_success "context flag" '$CLI_CMD --text "Settings" --from en --to de --context "Button label in app settings" --dry-run'
run_success "inline prompt overrides" '$CLI_CMD --text "Hello" --from en --to de --system-prompt "Translate {text} from {from} to {to}." --user-prompt "Text: {text}" --dry-run'
run_success "prompt overrides from files" '$CLI_CMD --text "Hello" --from en --to de --system-prompt @"$FIXTURES_DIR/prompts/system.txt" --user-prompt @"$FIXTURES_DIR/prompts/user.txt" --dry-run'
run_success "custom prompt no-lang" '$CLI_CMD --text "Hello" --from en --to de --system-prompt "Return only translation: {text}" --no-lang --dry-run'

print_section "Expected Success: Providers (Dry-Run)"
run_success "provider openai" '$CLI_CMD --text "Hello" --from en --to de --provider openai --dry-run'
run_success "provider anthropic" '$CLI_CMD --text "Hello" --from en --to de --provider anthropic --dry-run'
run_success "provider ollama" '$CLI_CMD --text "Hello" --from en --to de --provider ollama --dry-run'
run_success "provider openai-compatible explicit" '$CLI_CMD --text "Hello" --from en --to de --provider openai-compatible --base-url http://localhost:1234/v1 --model llama3.1 --api-key dummy --dry-run'
run_success "provider openai-compatible implicit via base-url" '$CLI_CMD --text "Hello" --from en --to de --base-url http://localhost:1234/v1 --model llama3.1 --api-key dummy --dry-run'
run_success "provider deepl dry-run" '$CLI_CMD --text "Hello" --from en --to de --provider deepl --dry-run'
run_success "named provider from config" '$CLI_CMD --text "Hello" --from en --to de --provider lmstudio --config "$FIXTURES_DIR/test-config.toml" --dry-run'
run_success "promptless deepl ignores prompt flags" '$CLI_CMD --text "Hello" --from en --to de --provider deepl --preset ui --context "Button label" --format markdown --system-prompt x --user-prompt y --dry-run'

print_section "Optional: Apple Providers (Dry-Run)"
if [[ "$RUN_APPLE" -eq 1 ]]; then
  run_success "provider apple-intelligence dry-run" '$CLI_CMD --text "Hello" --from en --to de --provider apple-intelligence --dry-run'
  run_success "provider apple-translate dry-run" '$CLI_CMD --text "Hello" --from en --to de --provider apple-translate --dry-run'
  run_success "promptless apple-translate ignores prompt flags" '$CLI_CMD --text "Hello" --from en --to de --provider apple-translate --preset ui --context "Button label" --format markdown --system-prompt x --user-prompt y --dry-run'
else
  skip_case "Apple provider dry-run tests (use --apple)"
fi

print_section "Expected Failures: Validation and Error Paths"
run_failure "text requires one positional" '$CLI_CMD --text --to de "one" "two"'
run_failure "text empty" '$CLI_CMD --text --to de ""'
run_failure "no input no stdin" '$CLI_CMD --from en --to de'
run_failure "mixed multi-arg invalid file path" '$CLI_CMD --from en --to de "$FIXTURES_DIR/plain.txt" not-a-file.txt'
run_failure "invalid target auto" '$CLI_CMD --text "Hello" --from en --to auto --dry-run'
run_failure "verbose and quiet conflict" '$CLI_CMD --text "Hello" --verbose --quiet --to de --dry-run'
run_failure "in-place with output conflict" '$CLI_CMD --from en --to de --in-place --output "$FIXTURES_DIR/out.txt" --dry-run "$FIXTURES_DIR/plain.txt"'
run_failure "in-place with suffix conflict" '$CLI_CMD --from en --to de --in-place --suffix _DE --dry-run "$FIXTURES_DIR/plain.txt"'
run_failure "output with multi file conflict" '$CLI_CMD --from en --to de --output "$FIXTURES_DIR/out.txt" --dry-run "$FIXTURES_DIR/plain.txt" "$FIXTURES_DIR/doc.md"'
run_failure "output with glob conflict" '$CLI_CMD --from en --to de --output "$FIXTURES_DIR/out.txt" --dry-run "$FIXTURES_DIR/*.md"'
run_failure "openai-compatible missing base/model" '$CLI_CMD --text "Hello" --from en --to de --provider openai-compatible --dry-run'
run_failure "unknown provider" '$CLI_CMD --text "Hello" --from en --to de --provider unknown-provider --dry-run'
run_failure "openai rejects base-url" '$CLI_CMD --text "Hello" --from en --to de --provider openai --base-url http://localhost:1234/v1 --dry-run'
run_failure "anthropic rejects base-url" '$CLI_CMD --text "Hello" --from en --to de --provider anthropic --base-url http://localhost:1234/v1 --dry-run'
run_failure "ollama rejects base-url" '$CLI_CMD --text "Hello" --from en --to de --provider ollama --base-url http://localhost:1234/v1 --dry-run'
run_failure "deepl rejects model" '$CLI_CMD --text "Hello" --from en --to de --provider deepl --model any --dry-run'
run_failure "deepl rejects base-url" '$CLI_CMD --text "Hello" --from en --to de --provider deepl --base-url http://localhost:1234/v1 --dry-run'
run_failure "apple-intelligence rejects model" '$CLI_CMD --text "Hello" --from en --to de --provider apple-intelligence --model any --dry-run'
run_failure "apple-intelligence rejects api-key" '$CLI_CMD --text "Hello" --from en --to de --provider apple-intelligence --api-key dummy --dry-run'
run_failure "apple-translate rejects model" '$CLI_CMD --text "Hello" --from en --to de --provider apple-translate --model any --dry-run'
run_failure "apple-translate rejects api-key" '$CLI_CMD --text "Hello" --from en --to de --provider apple-translate --api-key dummy --dry-run'

print_section "Optional: Live Provider Calls"
if [[ "$RUN_LIVE" -eq 1 ]]; then
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    run_success "live openai" '$CLI_CMD --text "Hello world" --from en --to de --provider openai'
  else
    skip_case "live openai (OPENAI_API_KEY not set)"
  fi

  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    run_success "live anthropic" '$CLI_CMD --text "Hello world" --from en --to de --provider anthropic'
  else
    skip_case "live anthropic (ANTHROPIC_API_KEY not set)"
  fi

  # Ollama/openai-compatible are optional local services; run only if user opted in and service exists.
  run_success "live ollama (if local service running)" '$CLI_CMD --text "Hello world" --from en --to de --provider ollama' || true
  run_success "live openai-compatible local (if local service running)" '$CLI_CMD --text "Hello world" --from en --to de --provider openai-compatible --base-url http://localhost:1234/v1 --model llama3.1' || true

  if [[ -n "${DEEPL_API_KEY:-}" ]]; then
    run_success "live deepl" '$CLI_CMD --text "Hello world" --from en --to de --provider deepl'
  else
    skip_case "live deepl (DEEPL_API_KEY not set)"
  fi

  if [[ "$RUN_APPLE" -eq 1 ]]; then
    run_success "live apple-intelligence" '$CLI_CMD --text "Hello world" --from en --to de --provider apple-intelligence' || true
    run_success "live apple-translate" '$CLI_CMD --text "Hello world" --from en --to de --provider apple-translate' || true
  fi
else
  skip_case "Live provider calls (use --live)"
fi

print_section "Summary"
echo "Expected-success: pass=$PASS_SUCCESS fail=$FAIL_SUCCESS"
echo "Expected-failure: pass=$PASS_FAILURE fail=$FAIL_FAILURE"
echo "Skipped: $SKIP_COUNT"
echo "Logs: $LOG_DIR"

if [[ $FAIL_SUCCESS -ne 0 || $FAIL_FAILURE -ne 0 ]]; then
  exit 1
fi

exit 0
