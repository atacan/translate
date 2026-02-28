import Foundation

enum TranslateHelp {
    static let root = """
USAGE:
  translate [OPTIONS] [TEXT]
  translate [OPTIONS] [FILE...]
  echo "text" | translate [OPTIONS]
  translate <subcommand> [OPTIONS]

EXAMPLES:
  translate --to en "Bonjour le monde"
  translate --to fr document.md
  translate --to ja *.md
  translate --to de --context "Button label in settings" document.md
  translate --provider apple-translate --to zh document.md
  translate --provider lm-studio --to fr document.md
  cat notes.txt | translate --to de
  translate --to fr --dry-run document.md
  translate --preset xcode-strings --to ja document.md

INPUT:
      --text                Force positional argument to be treated as literal text,
                            bypassing file detection (useful when a string matches a filename)
  TEXT                      Inline text to translate (if not a valid file path)
  FILE...                   One or more files to translate. Glob patterns (*.md) are
                            expanded by the tool on all platforms.
                            Note: globs always write output files, even if only one file matches.
                            For reliable parsing, place options before TEXT/FILE arguments.
  stdin                     Piped input is read when no positional arg is given

OUTPUT:
  -o, --output <FILE>       Write output to file [single explicit file or inline/stdin only]
  -i, --in-place            Overwrite input file(s) in place [file input only]
      --suffix <SUFFIX>     Output filename suffix before the final extension
                            [default for multiple files/globs: _{TO}, e.g. document_FR.md]
      --stream              Stream translated output as it arrives [stdout only]
  -y, --yes                 Skip all confirmation prompts
  -j, --jobs <N>            Files to translate in parallel [default: 1]

LANGUAGES:
  -f, --from <LANG>         Source language or "auto" [default: auto]
  -t, --to <LANG>           Target language [default: en]
                            Accepts: full names ("French"), ISO 639-1 ("fr"), BCP 47 ("zh-TW")
                            Note: "auto" is not valid for --to

PROVIDER:
  -p, --provider <name>     openai | anthropic | gemini | open-responses |
                            ollama | openai-compatible |
                            apple-intelligence | apple-translate | deepl |
                            <named-endpoint-from-config>
                            [default: openai, or value from config]
  -m, --model <ID>          Model ID [default: depends on provider]
      --base-url <URL>      API base URL [required for openai-compatible]
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
                              .md, .markdown, .mdx -> markdown
                              .html, .htm          -> html
                              all others, stdin    -> text
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
  GEMINI_API_KEY            API key for Gemini
  OPEN_RESPONSES_API_KEY    API key for Open Responses
  DEEPL_API_KEY             API key for DeepL
  TRANSLATE_CONFIG          Path to config file
  EDITOR                    Editor for `translate config edit`
"""
}
