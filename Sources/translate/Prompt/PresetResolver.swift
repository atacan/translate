import Foundation

struct PresetResolver {
    func activePresetName(cliPreset: String?, config: ResolvedConfig) -> String {
        cliPreset ?? config.defaultsPreset
    }

    func resolvePreset(named name: String, config: ResolvedConfig) throws -> PresetDefinition {
        let builtIns = BuiltInPresetStore.all()
        if let user = config.presets[name] {
            if let shadowed = builtIns[name] {
                return mergeWithFallback(userPreset: user, fallback: shadowed)
            }

            if let general = builtIns[BuiltInDefaults.preset] {
                return mergeWithFallback(userPreset: user, fallback: general)
            }

            return user
        }
        if let builtIn = builtIns[name] {
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

    private func mergeWithFallback(userPreset: PresetDefinition, fallback: PresetDefinition) -> PresetDefinition {
        return PresetDefinition(
            name: userPreset.name,
            source: .userDefined,
            description: userPreset.description ?? fallback.description,
            systemPrompt: userPreset.systemPrompt ?? (userPreset.systemPromptFile == nil ? fallback.systemPrompt : nil),
            systemPromptFile: userPreset.systemPromptFile,
            userPrompt: userPreset.userPrompt ?? (userPreset.userPromptFile == nil ? fallback.userPrompt : nil),
            userPromptFile: userPreset.userPromptFile,
            provider: userPreset.provider ?? fallback.provider,
            model: userPreset.model ?? fallback.model,
            from: userPreset.from ?? fallback.from,
            to: userPreset.to ?? fallback.to,
            format: userPreset.format ?? fallback.format
        )
    }

    private func mergeWithBuiltInFallback(userPreset: PresetDefinition, builtIns: [String: PresetDefinition]) -> PresetDefinition {
        guard let builtIn = builtIns[userPreset.name] else {
            return userPreset
        }
        return mergeWithFallback(userPreset: userPreset, fallback: builtIn)
    }
}
