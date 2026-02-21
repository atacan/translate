import Foundation
import TOMLKit

struct ConfigStore {
    func load(path: URL) throws -> TOMLTable {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return TOMLTable()
        }

        let data = try Data(contentsOf: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.runtime("Error: Config file '\(path.path)' contains invalid UTF-8.")
        }

        do {
            return try TOMLTable(string: text)
        } catch {
            throw AppError.runtime("Error: Failed to parse config file '\(path.path)': \(error)")
        }
    }

    func save(table: TOMLTable, path: URL) throws {
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: Data())
            #if canImport(Darwin)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            #endif
        }

        let text = table.convert(to: .toml)
        try text.write(to: path, atomically: true, encoding: .utf8)
    }
}
