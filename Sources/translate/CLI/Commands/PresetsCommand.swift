import ArgumentParser
import Foundation

struct PresetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "presets",
        abstract: "Manage and inspect presets",
        subcommands: [List.self, Show.self, Which.self],
        helpNames: .shortAndLong
    )

    struct List: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() throws {
            try runWithAppErrorHandling {
                let config = try loadConfig(self.config)
                let resolver = PresetResolver()
                let grouped = resolver.list(config: config)
                let active = resolver.activePresetName(cliPreset: nil, config: config)

                print("BUILT-IN PRESETS")
                for preset in grouped.builtIn {
                    let marker = preset.name == active ? "*" : " "
                    print("  \(preset.name.padding(toLength: 14, withPad: " ", startingAt: 0))\(marker)  \(preset.description ?? "")")
                }

                print("")
                print("USER-DEFINED PRESETS (in \(config.path.path))")
                for preset in grouped.user {
                    let marker = preset.name == active ? "*" : " "
                    print("  \(preset.name.padding(toLength: 14, withPad: " ", startingAt: 0))\(marker)  \(preset.description ?? "Custom preset")")
                }

                print("")
                print("  * = active default")
            }
        }
    }

    struct Show: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        @Argument var name: String

        mutating func run() throws {
            try runWithAppErrorHandling {
                let config = try loadConfig(self.config)
                let preset = try PresetResolver().resolvePreset(named: name, config: config)
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let templates = try PromptRenderer().resolvePresetTemplates(preset: preset, cwd: cwd)

                print("--- SYSTEM PROMPT ---")
                print(templates.systemPrompt)
                print("")
                print("--- USER PROMPT ---")
                print(templates.userPrompt)
            }
        }
    }

    struct Which: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() throws {
            try runWithAppErrorHandling {
                let config = try loadConfig(self.config)
                let name = PresetResolver().activePresetName(cliPreset: nil, config: config)
                let preset = try PresetResolver().resolvePreset(named: name, config: config)
                print("\(name) (\(preset.source.rawValue))")
            }
        }
    }

}

private func loadConfig(_ path: String?) throws -> ResolvedConfig {
    let resolvedPath = resolveConfigPath(path)
    let table = try ConfigStore().load(path: resolvedPath)
    let resolved = ConfigResolver().resolve(path: resolvedPath, table: table)
    let terminal = TerminalIO(quiet: false, verbose: false)
    for warning in ConfigResolver().namedProviderCollisionWarnings(resolved) {
        terminal.warn(warning.replacingOccurrences(of: "Warning: ", with: ""))
    }
    return resolved
}

private func runWithAppErrorHandling(_ body: () throws -> Void) throws {
    do {
        try body()
    } catch let appError as AppError {
        TerminalIO(quiet: false, verbose: false).error(appError.message)
        throw ExitCode(appError.exitCode.rawValue)
    }
}
