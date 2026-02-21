import Foundation

struct OutputWriter {
    let terminal: TerminalIO
    let prompter: ConfirmationPrompter

    func write(_ text: String, mode: OutputMode) throws -> URL? {
        switch mode {
        case .stdout:
            terminal.writeStdout(text)
            return nil
        case .singleFile(let destination):
            try writeFile(text: text, destination: destination)
            return destination
        case .perFile:
            throw AppError.runtime("Internal error: per-file output requires explicit target writing.")
        }
    }

    func writeFile(text: String, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try prompter.confirm("Output file '\(destination.lastPathComponent)' already exists. Overwrite? [y/N]")
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }
}
