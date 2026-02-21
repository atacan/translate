import Foundation

struct PromptRenderContext {
    let text: String
    let from: NormalizedLanguage
    let to: NormalizedLanguage
    let context: String
    let filename: String
    let format: ResolvedFormat
}

struct PromptRenderer {
    func resolvePrompts(
        preset: PresetDefinition,
        systemPromptOverride: String?,
        userPromptOverride: String?,
        cwd: URL,
        noLang: Bool
    ) throws -> (ResolvedPromptSet, [String]) {
        let systemTemplate = try resolveTemplate(
            inlineOrFile: systemPromptOverride,
            presetInline: preset.systemPrompt,
            presetFile: preset.systemPromptFile,
            cwd: cwd,
            promptLabel: "system"
        )

        let userTemplate = try resolveTemplate(
            inlineOrFile: userPromptOverride,
            presetInline: preset.userPrompt,
            presetFile: preset.userPromptFile,
            cwd: cwd,
            promptLabel: "user"
        )

        let customPromptActive = systemPromptOverride != nil || userPromptOverride != nil ||
            preset.systemPromptFile != nil || preset.userPromptFile != nil || preset.source == .userDefined

        var warnings: [String] = []
        if noLang && !customPromptActive {
            warnings.append("Warning: --no-lang has no effect when using default prompts.")
        }

        if customPromptActive && !noLang {
            let promptBody = "\(systemTemplate)\n\(userTemplate)"
            if !promptBody.contains("{from}") && !promptBody.contains("{to}") {
                warnings.append("Warning: Your custom prompt does not contain {from} or {to} placeholders. If you have hardcoded languages, pass --no-lang to suppress this warning.")
            }
        }

        return (ResolvedPromptSet(systemPrompt: systemTemplate, userPrompt: userTemplate, customPromptActive: customPromptActive), warnings)
    }

    func render(_ templates: ResolvedPromptSet, with context: PromptRenderContext) -> ResolvedPromptSet {
        let placeholders = placeholders(for: context)
        return ResolvedPromptSet(
            systemPrompt: substitute(templates.systemPrompt, placeholders: placeholders),
            userPrompt: substitute(templates.userPrompt, placeholders: placeholders),
            customPromptActive: templates.customPromptActive
        )
    }

    private func resolveTemplate(
        inlineOrFile: String?,
        presetInline: String?,
        presetFile: String?,
        cwd: URL,
        promptLabel: String
    ) throws -> String {
        if let inlineOrFile {
            return try resolveInlineOrFile(inlineOrFile, cwd: cwd, promptLabel: promptLabel)
        }

        if let presetInline {
            return presetInline
        }

        if let presetFile {
            return try resolveInlineOrFile("@\(presetFile)", cwd: cwd, promptLabel: promptLabel)
        }

        return ""
    }

    private func resolveInlineOrFile(_ value: String, cwd: URL, promptLabel: String) throws -> String {
        if !value.hasPrefix("@") {
            return value
        }

        let rawPath = String(value.dropFirst())
        let url = ConfigLocator.expandToAbsoluteURL(rawPath, cwd: cwd, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.runtime("Prompt file '\(rawPath)' not found.")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.runtime("Error: Failed to read \(promptLabel) prompt file '\(rawPath)': \(error)")
        }
    }

    private func placeholders(for context: PromptRenderContext) -> [String: String] {
        let trimmedContext = context.context.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "{from}": context.from.isAuto ? BuiltInDefaults.sourceLanguagePlaceholder : context.from.displayName,
            "{to}": context.to.displayName,
            "{text}": context.text,
            "{context}": trimmedContext,
            "{context_block}": trimmedContext.isEmpty ? "" : "\nAdditional context: \(trimmedContext)",
            "{filename}": context.filename,
            "{format}": context.format.promptValue,
        ]
    }

    private func substitute(_ template: String, placeholders: [String: String]) -> String {
        var output = template
        for (placeholder, value) in placeholders {
            output = output.replacingOccurrences(of: placeholder, with: value)
        }
        return output
    }
}
