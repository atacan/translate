import Foundation
import Glob

enum GlobExpander {
    static func looksLikeGlob(_ s: String) -> Bool {
        s.contains("*") || s.contains("?") || s.contains("[")
    }

    static func expand(pattern: String, cwd: URL) async throws -> [URL] {
        let globPattern = try Pattern(pattern)
        var files: [URL] = []
        for try await url in search(directory: cwd, include: [globPattern]) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                files.append(url.standardizedFileURL)
            }
        }

        let deduped = Array(Set(files)).sorted { $0.path < $1.path }
        if deduped.isEmpty {
            throw AppError.runtime("No files matched the pattern '\(pattern)'.")
        }
        return deduped
    }
}
