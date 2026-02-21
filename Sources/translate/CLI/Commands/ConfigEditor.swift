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

    static func makeProcess(editor: String, configPath: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, configPath]
        return process
    }
}
