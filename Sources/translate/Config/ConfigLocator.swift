import Foundation

enum ConfigLocator {
    static let defaultConfig = "~/.config/translate/config.toml"

    static func resolvedConfigPath(cli: String?, env: [String: String], cwd: URL, home: URL) -> URL {
        let raw = cli ?? env["TRANSLATE_CONFIG"] ?? defaultConfig
        return expandToAbsoluteURL(raw, cwd: cwd, homeDirectory: home)
    }

    static func expandToAbsoluteURL(_ raw: String, cwd: URL, homeDirectory: URL) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            let suffix = String(trimmed.dropFirst())
            return homeDirectory.appendingPathComponent(suffix)
                .standardizedFileURL
        }

        let url = URL(fileURLWithPath: trimmed)
        if url.path.hasPrefix("/") {
            return url.standardizedFileURL
        }

        return cwd.appendingPathComponent(trimmed).standardizedFileURL
    }
}
