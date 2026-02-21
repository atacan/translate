import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct TerminalIO {
    var quiet: Bool
    var verbose: Bool

    func writeStdout(_ text: String, terminator: String = "\n") {
        FileHandle.standardOutput.write(Data((text + terminator).utf8))
    }

    func writeStderr(_ text: String, terminator: String = "\n") {
        FileHandle.standardError.write(Data((text + terminator).utf8))
    }

    func info(_ text: String) {
        guard !quiet else { return }
        writeStderr("Info: \(text)")
    }

    func warn(_ text: String) {
        guard !quiet else { return }
        writeStderr("Warning: \(text)")
    }

    func error(_ text: String) {
        writeStderr(text)
    }

    var stdinIsTTY: Bool {
        #if canImport(Darwin)
        return isatty(STDIN_FILENO) == 1
        #else
        return true
        #endif
    }
}
