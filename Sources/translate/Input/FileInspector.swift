import Foundation

enum FileInspector {
    static func inspect(_ file: ResolvedInputFile) -> FileInspection {
        let data: Data
        do {
            data = try Data(contentsOf: file.path)
        } catch {
            return FileInspection(file: file, content: nil, warning: nil, error: "Input file '\(file.path.path)' not found.")
        }

        if appearsBinary(data) {
            return FileInspection(file: file, content: nil, warning: nil, error: "'\(file.path.lastPathComponent)' appears to be a binary file and cannot be translated.")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return FileInspection(file: file, content: nil, warning: nil, error: "'\(file.path.lastPathComponent)' contains invalid UTF-8. Please re-encode the file as UTF-8 before translating.")
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FileInspection(file: file, content: nil, warning: "'\(file.path.lastPathComponent)' is empty. Skipping.", error: nil)
        }

        return FileInspection(file: file, content: text, warning: nil, error: nil)
    }

    private static func appearsBinary(_ data: Data) -> Bool {
        if data.isEmpty {
            return false
        }

        let sample = data.prefix(8192)
        var controlCount = 0
        for byte in sample {
            if byte == 0 {
                return true
            }
            if byte < 7 || (byte > 13 && byte < 32) {
                controlCount += 1
            }
        }

        return Double(controlCount) / Double(sample.count) > 0.15
    }
}
