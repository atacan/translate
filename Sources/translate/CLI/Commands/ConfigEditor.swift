import Foundation

enum ConfigEditor {
    static var hostDefaultEditor: String {
        #if os(Windows)
        return "notepad"
        #else
        return "vi"
        #endif
    }

    static func resolvedEditor(environment: [String: String], defaultEditor: String = hostDefaultEditor) -> String {
        if let editor = environment["EDITOR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !editor.isEmpty {
            return editor
        }
        return defaultEditor
    }

    static func makeProcess(editor: String, configPath: String) throws -> Process {
        let editorArguments = try parseEditorCommand(editor)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = editorArguments + [configPath]
        return process
    }

    private static func parseEditorCommand(_ editor: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for scalar in editor.unicodeScalars {
            let character = Character(scalar)

            if isEscaping {
                current.unicodeScalars.append(scalar)
                isEscaping = false
                continue
            }

            if inSingleQuote {
                if character == "'" {
                    inSingleQuote = false
                } else {
                    current.unicodeScalars.append(scalar)
                }
                continue
            }

            if inDoubleQuote {
                if character == "\"" {
                    inDoubleQuote = false
                } else if character == "\\" {
                    isEscaping = true
                } else {
                    current.unicodeScalars.append(scalar)
                }
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if character == "'" {
                inSingleQuote = true
                continue
            }

            if character == "\"" {
                inDoubleQuote = true
                continue
            }

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !current.isEmpty {
                    args.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.unicodeScalars.append(scalar)
        }

        if isEscaping || inSingleQuote || inDoubleQuote {
            throw AppError.runtime("Invalid EDITOR command: unmatched escape or quote.")
        }

        if !current.isEmpty {
            args.append(current)
        }

        if args.isEmpty {
            throw AppError.runtime("Invalid EDITOR command: no executable found.")
        }

        return args
    }
}
