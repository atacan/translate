import Foundation

struct InputResolver {
    func resolve(positional: [String], forceText: Bool, terminal: TerminalIO, cwd: URL) async throws -> InputMode {
        if forceText {
            guard positional.count == 1 else {
                throw AppError.invalidArguments("--text requires exactly one positional argument.")
            }
            guard !positional[0].isEmpty else {
                throw AppError.runtime("Error: Input text is empty.")
            }
            return .inlineText(positional[0])
        }

        if positional.isEmpty {
            guard !terminal.stdinIsTTY else {
                throw AppError.invalidArguments("No input provided. Provide text, file path(s), or pipe stdin.")
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.runtime("Error: Input text is empty.")
            }
            return .stdin(text)
        }

        if positional.count == 1 {
            let candidate = positional[0]
            if GlobExpander.looksLikeGlob(candidate) {
                let urls = try await GlobExpander.expand(pattern: candidate, cwd: cwd)
                return .files(urls.map { ResolvedInputFile(path: $0, matchedByGlob: true) }, cameFromGlob: true)
            }

            let singlePath = resolvedFileURL(candidate, cwd: cwd)
            if isExistingFile(singlePath) {
                return .files([ResolvedInputFile(path: singlePath, matchedByGlob: false)], cameFromGlob: false)
            }

            guard !candidate.isEmpty else {
                throw AppError.runtime("Error: Input text is empty.")
            }
            return .inlineText(candidate)
        }

        var files: [ResolvedInputFile] = []
        var sawGlob = false

        for arg in positional {
            if GlobExpander.looksLikeGlob(arg) {
                sawGlob = true
                let urls = try await GlobExpander.expand(pattern: arg, cwd: cwd)
                files.append(contentsOf: urls.map { ResolvedInputFile(path: $0, matchedByGlob: true) })
                continue
            }

            let path = resolvedFileURL(arg, cwd: cwd)
            if isExistingFile(path) {
                files.append(ResolvedInputFile(path: path, matchedByGlob: false))
            } else {
                throw AppError.invalidArguments("Argument '\(arg)' is not a valid file path. To translate a literal string, use --text.")
            }
        }

        if files.isEmpty {
            throw AppError.runtime("Error: Input text is empty.")
        }

        let deduped = Array(Set(files)).sorted { $0.path.path < $1.path.path }
        return .files(deduped, cameFromGlob: sawGlob)
    }

    private func resolvedFileURL(_ raw: String, cwd: URL) -> URL {
        let url = URL(fileURLWithPath: raw)
        if url.path.hasPrefix("/") {
            return url.standardizedFileURL
        }
        return cwd.appendingPathComponent(raw).standardizedFileURL
    }

    private func isExistingFile(_ path: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
}
