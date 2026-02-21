import Foundation
import Glob

enum GlobExpander {
    static func looksLikeGlob(_ s: String) -> Bool {
        s.contains("*") || s.contains("?") || s.contains("[")
    }

    static func expand(pattern: String, cwd: URL) async throws -> [URL] {
        let plan = searchPlan(pattern: pattern, cwd: cwd)
        let globPattern = try Pattern(plan.includePattern)
        var files: [URL] = []
        for try await url in search(directory: plan.baseDirectory, include: [globPattern]) {
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

    private static func searchPlan(pattern: String, cwd: URL) -> (baseDirectory: URL, includePattern: String) {
        guard let firstGlobIndex = pattern.firstIndex(where: isGlobCharacter(_:)) else {
            return (cwd, pattern)
        }

        let prefixBeforeFirstGlob = pattern[..<firstGlobIndex]
        guard let slashBeforeGlob = prefixBeforeFirstGlob.lastIndex(of: "/") else {
            return (cwd, pattern)
        }

        let prefix = String(pattern[..<slashBeforeGlob])
        let patternStart = pattern.index(after: slashBeforeGlob)
        let remainder = String(pattern[patternStart...])

        let baseDirectory: URL
        if prefix.isEmpty, pattern.hasPrefix("/") {
            baseDirectory = URL(fileURLWithPath: "/")
        } else {
            if prefix.hasPrefix("/") {
                baseDirectory = URL(fileURLWithPath: prefix)
            } else {
                baseDirectory = cwd.appendingPathComponent(prefix)
            }
        }

        return (baseDirectory.standardizedFileURL, remainder)
    }

    private static func isGlobCharacter(_ c: Character) -> Bool {
        c == "*" || c == "?" || c == "["
    }
}
