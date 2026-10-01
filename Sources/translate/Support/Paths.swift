import Foundation

func resolveConfigPath(_ cliPath: String?) -> URL {
    ConfigLocator.resolvedConfigPath(
        cli: cliPath,
        env: ProcessInfo.processInfo.environment,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: FileManager.default.homeDirectoryForCurrentUser
    )
}

func loadSelectedConfig(_ cliPath: String?) throws -> ResolvedConfig {
    let path = resolveConfigPath(cliPath)
    let table = try ConfigStore().load(
        path: path,
        requireExists: ConfigLocator.isExplicitlySelected(cli: cliPath, env: ProcessInfo.processInfo.environment)
    )
    return ConfigResolver().resolve(path: path, table: table)
}

func emitConfigWarnings(_ config: ResolvedConfig, terminal: TerminalIO) {
    for warning in ConfigResolver().warnings(config) {
        terminal.warn(warning.replacingOccurrences(of: "Warning: ", with: ""))
    }
}
