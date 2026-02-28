import Foundation
import TOMLKit

struct ConfigResolver {
    func resolve(path: URL, table: TOMLTable) -> ResolvedConfig {
        let defaultsProvider = string(in: table, at: ["defaults", "provider"]) ?? BuiltInDefaults.provider
        let defaultsFrom = string(in: table, at: ["defaults", "from"]) ?? BuiltInDefaults.from
        let defaultsTo = string(in: table, at: ["defaults", "to"]) ?? BuiltInDefaults.to
        let defaultsPreset = string(in: table, at: ["defaults", "preset"]) ?? BuiltInDefaults.preset
        let defaultsFormat = FormatHint(rawValue: string(in: table, at: ["defaults", "format"]) ?? BuiltInDefaults.format) ?? .auto
        let defaultsStream = bool(in: table, at: ["defaults", "stream"]) ?? BuiltInDefaults.stream
        let defaultsYes = bool(in: table, at: ["defaults", "yes"]) ?? BuiltInDefaults.yes
        let defaultsJobs = int(in: table, at: ["defaults", "jobs"]) ?? BuiltInDefaults.jobs

        let timeoutSeconds = max(1, int(in: table, at: ["network", "timeout_seconds"]) ?? BuiltInNetwork.timeoutSeconds)
        let retries = max(0, int(in: table, at: ["network", "retries"]) ?? BuiltInNetwork.retries)
        let retryBaseDelaySeconds = max(1, int(in: table, at: ["network", "retry_base_delay_seconds"]) ?? BuiltInNetwork.retryBaseDelaySeconds)
        let network = NetworkRuntimeConfig(
            timeoutSeconds: timeoutSeconds,
            retries: retries,
            retryBaseDelaySeconds: retryBaseDelaySeconds
        )

        let providerEntries = parseProviderEntries(table: table)
        let namedOpenAICompatible = parseNamedOpenAICompatible(table: table)
        let presets = parseUserPresets(table: table)

        return ResolvedConfig(
            path: path,
            table: table,
            defaultsProvider: defaultsProvider,
            defaultsFrom: defaultsFrom,
            defaultsTo: defaultsTo,
            defaultsPreset: defaultsPreset,
            defaultsFormat: defaultsFormat,
            defaultsStream: defaultsStream,
            defaultsYes: defaultsYes,
            defaultsJobs: max(1, defaultsJobs),
            network: network,
            providers: providerEntries,
            namedOpenAICompatible: namedOpenAICompatible,
            presets: presets
        )
    }

    func namedProviderCollisionWarnings(_ config: ResolvedConfig) -> [String] {
        var warnings: [String] = []
        for name in config.namedOpenAICompatible.keys.sorted() {
            if ProviderID.builtInNames.contains(name) {
                warnings.append("Warning: Named endpoint '\(name)' in config has the same name as a built-in provider and will never be used. Rename the endpoint to avoid this conflict.")
            }
        }
        return warnings
    }

    func effectiveConfigTable(_ config: ResolvedConfig) -> TOMLTable {
        let out = TOMLTable()

        let defaults = TOMLTable()
        defaults["provider"] = config.defaultsProvider
        defaults["from"] = config.defaultsFrom
        defaults["to"] = config.defaultsTo
        defaults["preset"] = config.defaultsPreset
        defaults["format"] = config.defaultsFormat.rawValue
        defaults["stream"] = config.defaultsStream
        defaults["yes"] = config.defaultsYes
        defaults["jobs"] = config.defaultsJobs
        out["defaults"] = defaults

        let network = TOMLTable()
        network["timeout_seconds"] = config.network.timeoutSeconds
        network["retries"] = config.network.retries
        network["retry_base_delay_seconds"] = config.network.retryBaseDelaySeconds
        out["network"] = network

        if let providersTable = config.table["providers"]?.table {
            out["providers"] = providersTable
        }
        if let presetsTable = config.table["presets"]?.table {
            out["presets"] = presetsTable
        }

        return out
    }

    private func parseProviderEntries(table: TOMLTable) -> [String: ProviderConfigEntry] {
        var output: [String: ProviderConfigEntry] = [:]

        let providers: [ProviderID] = [.openai, .anthropic, .gemini, .openResponses, .ollama, .deepl]
        for provider in providers {
            let path = ["providers", provider.rawValue]
            output[provider.rawValue] = ProviderConfigEntry(
                baseURL: string(in: table, at: path + ["base_url"]),
                model: string(in: table, at: path + ["model"]),
                apiKey: string(in: table, at: path + ["api_key"])
            )
        }

        let openAICompatPath = ["providers", ProviderID.openAICompatible.rawValue]
        output[ProviderID.openAICompatible.rawValue] = ProviderConfigEntry(
            baseURL: string(in: table, at: openAICompatPath + ["base_url"]),
            model: string(in: table, at: openAICompatPath + ["model"]),
            apiKey: string(in: table, at: openAICompatPath + ["api_key"])
        )

        return output
    }

    private func parseNamedOpenAICompatible(table: TOMLTable) -> [String: ProviderConfigEntry] {
        guard let parent = table["providers"]?[ProviderID.openAICompatible.rawValue]?.table else {
            return [:]
        }

        var output: [String: ProviderConfigEntry] = [:]
        for key in parent.keys {
            guard let candidate = parent[key]?.table else { continue }
            if key == "base_url" || key == "model" || key == "api_key" {
                continue
            }

            output[key] = ProviderConfigEntry(
                baseURL: candidate["base_url"]?.string,
                model: candidate["model"]?.string,
                apiKey: candidate["api_key"]?.string
            )
        }
        return output
    }

    private func parseUserPresets(table: TOMLTable) -> [String: PresetDefinition] {
        guard let presetsTable = table["presets"]?.table else {
            return [:]
        }

        var output: [String: PresetDefinition] = [:]
        for key in presetsTable.keys {
            guard let presetTable = presetsTable[key]?.table else { continue }
            let preset = PresetDefinition(
                name: key,
                source: .userDefined,
                description: nil,
                systemPrompt: presetTable["system_prompt"]?.string,
                systemPromptFile: presetTable["system_prompt_file"]?.string,
                userPrompt: presetTable["user_prompt"]?.string,
                userPromptFile: presetTable["user_prompt_file"]?.string,
                provider: presetTable["provider"]?.string,
                model: presetTable["model"]?.string,
                from: presetTable["from"]?.string,
                to: presetTable["to"]?.string,
                format: presetTable["format"]?.string
            )
            output[key] = preset
        }
        return output
    }

    private func value(in table: TOMLTable, at path: [String]) -> TOMLValueConvertible? {
        var current: TOMLValueConvertible = table
        for segment in path {
            guard let next = current[segment] else { return nil }
            current = next
        }
        return current
    }

    private func string(in table: TOMLTable, at path: [String]) -> String? {
        value(in: table, at: path)?.string
    }

    private func int(in table: TOMLTable, at path: [String]) -> Int? {
        value(in: table, at: path)?.int
    }

    private func bool(in table: TOMLTable, at path: [String]) -> Bool? {
        value(in: table, at: path)?.bool
    }
}
