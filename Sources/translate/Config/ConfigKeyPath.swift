import Foundation
import TOMLKit

enum ConfigKeyPath {
    static func get(table: TOMLTable, key: String) -> TOMLValueConvertible? {
        let segments = segments(for: key)
        guard !segments.isEmpty else { return nil }

        var current: TOMLValueConvertible = table
        for segment in segments {
            guard let next = current[segment] else { return nil }
            current = next
        }
        return current
    }

    static func set(table: TOMLTable, key: String, value: TOMLValueConvertible) {
        let segments = segments(for: key)
        guard !segments.isEmpty else { return }
        set(table: table, segments: segments, value: value, depth: 0)
    }

    @discardableResult
    static func unset(table: TOMLTable, key: String) -> Bool {
        let segments = segments(for: key)
        guard !segments.isEmpty else { return false }
        return unset(table: table, segments: segments, depth: 0)
    }

    static func segments(for key: String) -> [String] {
        key
            .split(separator: ".")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseScalar(_ raw: String) -> TOMLValueConvertible {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered == "true" {
            return true
        }
        if lowered == "false" {
            return false
        }
        if let intValue = Int(trimmed) {
            return intValue
        }
        if let doubleValue = Double(trimmed), trimmed.contains(".") {
            return doubleValue
        }
        return trimmed
    }

    static func toPrintable(_ value: TOMLValueConvertible) -> String {
        if let str = value.string { return str }
        if let int = value.int { return String(int) }
        if let double = value.double { return String(double) }
        if let bool = value.bool { return bool ? "true" : "false" }
        if let table = value.table { return table.convert(to: .toml).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let array = value.array { return array.debugDescription }
        return value.debugDescription
    }

    private static func set(table: TOMLTable, segments: [String], value: TOMLValueConvertible, depth: Int) {
        if depth == segments.count - 1 {
            table[segments[depth]] = value
            return
        }

        let key = segments[depth]
        let child = table[key]?.table ?? TOMLTable()
        set(table: child, segments: segments, value: value, depth: depth + 1)
        table[key] = child
    }

    @discardableResult
    private static func unset(table: TOMLTable, segments: [String], depth: Int) -> Bool {
        let key = segments[depth]
        if depth == segments.count - 1 {
            return table.remove(at: key) != nil
        }

        guard let child = table[key]?.table else { return false }
        let removed = unset(table: child, segments: segments, depth: depth + 1)
        if child.isEmpty {
            _ = table.remove(at: key)
        } else {
            table[key] = child
        }
        return removed
    }
}
