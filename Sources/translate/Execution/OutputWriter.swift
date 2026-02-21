import Foundation

struct OutputWriter {
    let terminal: TerminalIO
    let prompter: ConfirmationPrompter
    let skipOverwriteConfirmation: Bool

    init(terminal: TerminalIO, prompter: ConfirmationPrompter, skipOverwriteConfirmation: Bool = false) {
        self.terminal = terminal
        self.prompter = prompter
        self.skipOverwriteConfirmation = skipOverwriteConfirmation
    }

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
        if !skipOverwriteConfirmation, FileManager.default.fileExists(atPath: destination.path) {
            try prompter.confirm("Output file '\(destination.lastPathComponent)' already exists. Overwrite? [y/N]")
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }
}
