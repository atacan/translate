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
            system: origin(override: options.systemPrompt, inline: userPreset?.systemPrompt, file: userPreset?.systemPromptFile),
            user: origin(override: options.userPrompt, inline: userPreset?.userPrompt, file: userPreset?.userPromptFile)
        )
    }
}
