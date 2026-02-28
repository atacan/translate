import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Config file path.")
    var config: String?

    @Flag(name: [.short, .long], help: "Suppress warnings.")
    var quiet = false

    @Flag(name: [.short, .long], help: "Verbose diagnostics.")
    var verbose = false
}

struct TranslateOptions: ParsableArguments {
    @Argument(help: "Input text or file path(s).")
    var input: [String] = []

    @Flag(name: .long, help: "Force positional argument to be treated as literal text.")
    var text = false

    @Option(name: [.short, .long], help: "Write output to file.")
    var output: String?

    @Flag(name: [.short, .long], help: "Overwrite input file(s) in place.")
    var inPlace = false

    @Option(name: .long, help: "Output filename suffix.")
    var suffix: String?

    @Flag(name: .long, help: "Stream translated output to stdout as it arrives.")
    var stream = false

    @Flag(name: [.short, .long], help: "Skip confirmation prompts.")
    var yes = false

    @Option(name: [.short, .long], help: "Parallel jobs for multiple file input.")
    var jobs: Int?

    @Option(name: [.short, .long], help: "Source language.")
    var from: String?

    @Option(name: [.short, .long], help: "Target language.")
    var to: String?

    @Option(name: [.short, .long], help: "Provider name.")
    var provider: String?

    @Option(name: [.short, .long], help: "Model identifier.")
    var model: String?

    @Option(name: .long, help: "API base URL.")
    var baseURL: String?

    @Option(name: .long, help: "API key.")
    var apiKey: String?

    @Option(name: .long, help: "Prompt preset name.")
    var preset: String?

    @Option(name: .long, help: "System prompt template or @file.")
    var systemPrompt: String?

    @Option(name: .long, help: "User prompt template or @file.")
    var userPrompt: String?

    @Option(name: [.short, .long], help: "Additional context.")
    var context: String?

    @Flag(name: .long, help: "Suppress language-placeholder warning.")
    var noLang = false

    @Option(name: .long, help: "Input format hint.")
    var format: FormatHint?

    @Flag(name: .long, help: "Print resolved prompts and provider/model without calling APIs.")
    var dryRun = false
}
