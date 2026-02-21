import ArgumentParser
import Foundation

struct PresetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "presets",
        abstract: "Manage and inspect presets",
        subcommands: [List.self, Show.self, Which.self]
    )

    struct List: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() throws {
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
                print("  \(preset.name.padding(toLength: 14, withPad: " ", startingAt: 0))   \(preset.description ?? "Custom preset")")
            }

            print("")
            print("  * = active default")
        }
    }

    struct Show: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        @Argument var name: String

        mutating func run() throws {
            let config = try loadConfig(self.config)
            let preset = try PresetResolver().resolvePreset(named: name, config: config)

            print("--- SYSTEM PROMPT ---")
            print(preset.systemPrompt ?? "")
            print("")
            print("--- USER PROMPT ---")
            print(preset.userPrompt ?? "")
        }
    }

    struct Which: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() throws {
            let config = try loadConfig(self.config)
            let name = PresetResolver().activePresetName(cliPreset: nil, config: config)
            let preset = try PresetResolver().resolvePreset(named: name, config: config)
            print("\(name) (\(preset.source.rawValue))")
        }
    }

}

private func loadConfig(_ path: String?) throws -> ResolvedConfig {
    let resolvedPath = resolveConfigPath(path)
    let table = try ConfigStore().load(path: resolvedPath)
    return ConfigResolver().resolve(path: resolvedPath, table: table)
}
