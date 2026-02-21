import ArgumentParser
import Foundation
import TOMLKit

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage configuration",
        subcommands: [Show.self, Path.self, Get.self, Set.self, Unset.self, Edit.self]
    )

    struct Show: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() throws {
            try runWithAppErrorHandling {
                let path = resolveConfigPath(config)
                let table = try ConfigStore().load(path: path)
                let resolved = ConfigResolver().resolve(path: path, table: table)
                emitNamedProviderCollisionWarnings(config: resolved)
                print(ConfigResolver().effectiveConfigTable(resolved).convert(to: .toml))
            }
        }
    }

    struct Path: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() {
            let path = resolveConfigPath(config)
            print(path.path)
        }
    }

    struct Get: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        @Argument var key: String

        mutating func run() throws {
            try runWithAppErrorHandling {
                let path = resolveConfigPath(config)
                let table = try ConfigStore().load(path: path)
                let resolved = ConfigResolver().resolve(path: path, table: table)
                emitNamedProviderCollisionWarnings(config: resolved)
                guard let value = ConfigKeyPath.get(table: table, key: key) else {
                    throw AppError.runtime("Key '\(key)' not found.")
                }
                print(ConfigKeyPath.toPrintable(value))
            }
        }
    }

    struct Set: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        @Argument var key: String
        @Argument var value: String

        mutating func run() throws {
            try runWithAppErrorHandling {
                let path = resolveConfigPath(config)
                let store = ConfigStore()
                let table = try store.load(path: path)
                let resolved = ConfigResolver().resolve(path: path, table: table)
                emitNamedProviderCollisionWarnings(config: resolved)
                ConfigKeyPath.set(table: table, key: key, value: ConfigKeyPath.parseScalar(value))
                try store.save(table: table, path: path)
            }
        }
    }

    struct Unset: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        @Argument var key: String

        mutating func run() throws {
            try runWithAppErrorHandling {
                let path = resolveConfigPath(config)
                let store = ConfigStore()
                let table = try store.load(path: path)
                let resolved = ConfigResolver().resolve(path: path, table: table)
                emitNamedProviderCollisionWarnings(config: resolved)
                _ = ConfigKeyPath.unset(table: table, key: key)
                try store.save(table: table, path: path)
            }
        }
    }

    struct Edit: ParsableCommand {
        @Option(name: .long, help: "Config file path.")
        var config: String?

        mutating func run() throws {
            try runWithAppErrorHandling {
                let path = resolveConfigPath(config)
                let store = ConfigStore()
                let table = try store.load(path: path)
                let resolved = ConfigResolver().resolve(path: path, table: table)
                emitNamedProviderCollisionWarnings(config: resolved)
                try store.save(table: table, path: path)

                #if os(Windows)
                let fallbackEditor = "notepad"
                #else
                let fallbackEditor = "vi"
                #endif
                let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? fallbackEditor

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [editor, path.path]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    throw AppError.runtime("editor exited with status \(process.terminationStatus).")
                }
            }
        }
    }
}

private func emitNamedProviderCollisionWarnings(config: ResolvedConfig) {
    let terminal = TerminalIO(quiet: false, verbose: false)
    for warning in ConfigResolver().namedProviderCollisionWarnings(config) {
        terminal.warn(warning.replacingOccurrences(of: "Warning: ", with: ""))
    }
}

private func runWithAppErrorHandling(_ body: () throws -> Void) throws {
    do {
        try body()
    } catch let appError as AppError {
        TerminalIO(quiet: false, verbose: false).error(appError.message)
        throw ExitCode(appError.exitCode.rawValue)
    }
}
