import TOMLKit

// Schema diagnostics report keys and expected shapes, never configured values.
enum ConfigDiagnostics {
    static func warnings(table: TOMLTable) -> [String] {
        var output: [String] = []
        let sections: Set<String> = ["defaults", "network", "providers", "presets"]
        for key in table.keys.sorted() where !sections.contains(key) {
            output.append("Warning: Unknown config key '\(key)'. Use defaults, network, providers, or presets; prompt templates belong under presets.<name>.")
        }

        if let value = table["defaults"] {
            if let defaults = value.table {
                let schema: [String: Kind] = ["provider": .string, "from": .string, "to": .string,
                                              "preset": .string, "format": .string, "stream": .bool,
                                              "yes": .bool, "jobs": .int]
                inspect(defaults, prefix: "defaults", schema: schema, output: &output)
                checkFormat(defaults, prefix: "defaults", output: &output)
                if let name = defaults["preset"]?.string,
                   BuiltInPresetStore.all()[name] == nil, table["presets"]?[name]?.table == nil {
                    output.append("Warning: Config key 'defaults.preset' names an unknown preset. Run translate presets list or define it under presets.<name>.")
                }
            } else {
                output.append("Warning: Config key 'defaults' must be a table. Use [defaults].")
            }
        }
        if let value = table["presets"] {
            if let presets = value.table {
                let keys = ["description", "system_prompt", "system_prompt_file", "user_prompt", "user_prompt_file",
                            "provider", "model", "from", "to", "format"]
                let schema = Dictionary(uniqueKeysWithValues: keys.map { ($0, Kind.string) })
                for name in presets.keys.sorted() {
                    let prefix = "presets.\(name)"
                    if let preset = presets[name]?.table {
                        inspect(preset, prefix: prefix, schema: schema, output: &output)
                        checkFormat(preset, prefix: prefix, output: &output)
                    } else {
                        output.append("Warning: Config key '\(prefix)' must be a table. Use [\(prefix)].")
                    }
                }
            } else {
                output.append("Warning: Config key 'presets' must be a table. Use [presets.<name>].")
            }
        }
        return output
    }

    private enum Kind: String {
        case string, bool = "boolean", int = "integer"

        func accepts(_ value: TOMLValueConvertible) -> Bool {
            switch self {
            case .string: return value.string != nil
            case .bool: return value.bool != nil
            case .int: return value.int != nil
            }
        }
    }

    private static func inspect(_ table: TOMLTable, prefix: String, schema: [String: Kind], output: inout [String]) {
        for key in table.keys.sorted() {
            guard let expected = schema[key] else {
                output.append("Warning: Unknown config key '\(prefix).\(key)'. Supported keys: \(schema.keys.sorted().joined(separator: ", ")).")
                continue
            }
            if let value = table[key], !expected.accepts(value) {
                output.append("Warning: Config key '\(prefix).\(key)' must be a \(expected.rawValue); the value is ignored.")
            }
        }
    }

    private static func checkFormat(_ table: TOMLTable, prefix: String, output: inout [String]) {
        if let format = table["format"]?.string, FormatHint(rawValue: format) == nil {
            output.append("Warning: Config key '\(prefix).format' must be auto, text, markdown, or html; the value is ignored.")
        }
    }
}
