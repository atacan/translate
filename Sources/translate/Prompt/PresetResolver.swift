import Foundation

struct PresetResolver {
    func activePresetName(cliPreset: String?, config: ResolvedConfig) -> String {
        cliPreset ?? config.defaultsPreset
    }

    func resolvePreset(named name: String, config: ResolvedConfig) throws -> PresetDefinition {
        if let user = config.presets[name] {
            return mergeWithBuiltInFallback(userPreset: user, builtIns: BuiltInPresetStore.all())
        }
        if let builtIn = BuiltInPresetStore.all()[name] {
            return builtIn
        }
        throw AppError.invalidArguments("Unknown preset '\(name)'. Run translate presets list to see available presets.")
    }

    func list(config: ResolvedConfig) -> (builtIn: [PresetDefinition], user: [PresetDefinition]) {
        let builtInMap = BuiltInPresetStore.all()

        var builtIn: [PresetDefinition] = builtInMap.values.sorted { $0.name < $1.name }
        for index in builtIn.indices {
            if let userShadow = config.presets[builtIn[index].name] {
                builtIn[index] = mergeWithBuiltInFallback(userPreset: userShadow, builtIns: builtInMap)
            }
        }

        let userOnly = config.presets.values
            .filter { builtInMap[$0.name] == nil }
            .sorted { $0.name < $1.name }

        return (builtIn, userOnly)
    }

    private func mergeWithBuiltInFallback(userPreset: PresetDefinition, builtIns: [String: PresetDefinition]) -> PresetDefinition {
        guard let builtIn = builtIns[userPreset.name] else {
            return userPreset
        }

        return PresetDefinition(
            name: userPreset.name,
            source: .userDefined,
            description: userPreset.description ?? builtIn.description,
            systemPrompt: userPreset.systemPrompt ?? builtIn.systemPrompt,
            systemPromptFile: userPreset.systemPromptFile,
            userPrompt: userPreset.userPrompt ?? builtIn.userPrompt,
            userPromptFile: userPreset.userPromptFile,
            provider: userPreset.provider ?? builtIn.provider,
            model: userPreset.model ?? builtIn.model,
            from: userPreset.from ?? builtIn.from,
            to: userPreset.to ?? builtIn.to,
            format: userPreset.format ?? builtIn.format
        )
    }
}
