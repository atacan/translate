import Foundation

struct ResponseSanitizer {
    static func stripWrappingCodeFence(_ text: String) -> (text: String, stripped: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return (text, false)
        }

        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else {
            return (text, false)
        }

        let first = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        let last = lines.removeLast().trimmingCharacters(in: .whitespaces)
        guard first.hasPrefix("```"), last == "```" else {
            return (text, false)
        }

        return (lines.joined(separator: "\n"), true)
    }
}
