import Foundation

struct AppError: Error, CustomStringConvertible {
    let message: String
    let exitCode: ExitCodeMap

    var description: String {
        message
    }

    static func invalidArguments(_ message: String) -> Self {
        Self(message: message, exitCode: .invalidArguments)
    }

    static func runtime(_ message: String) -> Self {
        Self(message: message, exitCode: .runtimeError)
    }

    static func aborted(_ message: String) -> Self {
        Self(message: message, exitCode: .aborted)
    }
}
