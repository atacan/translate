import Foundation

struct PromptOrigins: Sendable {
    let system: String
    let user: String

    static func presetSelection(cliPreset: String?, config: ResolvedConfig, isCatalog: Bool) -> String {
        if cliPreset != nil { return "CLI --preset" }
        if config.table["defaults"]?["preset"]?.string != nil { return "config defaults.preset" }
        if config.presets[config.defaultsPreset] != nil { return "customized config default preset" }
        return isCatalog ? "implicit catalog default" : "built-in default"
    }

    static func resolve(preset: PresetDefinition, config: ResolvedConfig, options: TranslateOptions) -> Self {
        resolve(preset: preset, config: config, systemOverride: options.systemPrompt, userOverride: options.userPrompt)
    }

    static func resolve(preset: PresetDefinition, config: ResolvedConfig, systemOverride: String? = nil, userOverride: String? = nil) -> Self {
        let userPreset = config.presets[preset.name]
        let fallbackName = BuiltInPresetStore.all()[preset.name] == nil ? BuiltInDefaults.preset : preset.name
        func origin(override: String?, inline: String?, file: String?) -> String {
            if let override {
                return override.hasPrefix("@") ? "CLI file \(override.dropFirst())" : "CLI inline"
            }
            if inline != nil { return "user preset \(preset.name) inline" }
            if let file { return "user preset \(preset.name) file \(file)" }
            return "built-in preset \(fallbackName)"
        }
        return Self(
            system: origin(override: systemOverride, inline: userPreset?.systemPrompt, file: userPreset?.systemPromptFile),
            user: origin(override: userOverride, inline: userPreset?.userPrompt, file: userPreset?.userPromptFile)
        )
    }
}
