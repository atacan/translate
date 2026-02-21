import Foundation

struct ConfirmationPrompter {
    let terminal: TerminalIO
    let assumeYes: Bool

    func confirm(_ prompt: String) throws {
        if assumeYes {
            return
        }

        guard terminal.stdinIsTTY else {
            throw AppError.aborted("Error: Interactive confirmation required but stdin is not a TTY. Use --yes to confirm non-interactively.")
        }

        terminal.writeStderr(prompt, terminator: " ")
        let response = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if response != "y" && response != "yes" {
            throw AppError.aborted("Aborted.")
        }
    }
}
