import ArgumentParser
import Foundation

struct TranslateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "translate",
        abstract: "Translate text and files with configurable providers and prompt presets.",
        version: "0.1.1",
        subcommands: [TranslateRunCommand.self, ConfigCommand.self, PresetsCommand.self],
        defaultSubcommand: TranslateRunCommand.self,
        helpNames: []
    )

    mutating func run() async throws {
        throw CleanExit.helpRequest()
    }
}

struct TranslateRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "translate",
        shouldDisplay: false
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var options: TranslateOptions
    @Flag(name: [.customShort("h"), .customLong("help")], help: "Show this help.")
    var showHelp = false

    mutating func run() async throws {
        if showHelp {
            TerminalIO(quiet: false, verbose: false).writeStdout(TranslateHelp.root)
            return
        }

        do {
            try await TranslationOrchestrator().run(options: options, global: global)
        } catch let appError as AppError {
            TerminalIO(quiet: false, verbose: false).error(appError.message)
            throw ExitCode(appError.exitCode.rawValue)
        } catch let providerError as ProviderError {
            TerminalIO(quiet: false, verbose: false).error(providerError.message)
            throw ExitCode(ExitCodeMap.runtimeError.rawValue)
        }
    }
}
