import Foundation

func resolveConfigPath(_ cliPath: String?) -> URL {
    ConfigLocator.resolvedConfigPath(
        cli: cliPath,
        env: ProcessInfo.processInfo.environment,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: FileManager.default.homeDirectoryForCurrentUser
    )
}
