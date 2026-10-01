import Foundation

struct PromptRenderContext {
    let text: String
    let from: NormalizedLanguage
    let to: NormalizedLanguage
    let context: String
    let filename: String
    let format: ResolvedFormat
    let stringKey: String
    let comment: String
    let segment: String

    init(
        text: String,
        from: NormalizedLanguage,
        to: NormalizedLanguage,
        context: String,
        filename: String,
        format: ResolvedFormat,
        stringKey: String = "",
        comment: String = "",
        segment: String = ""
    ) {
        self.text = text
        self.from = from
        self.to = to
        self.context = context
        self.filename = filename
        self.format = format
        self.stringKey = stringKey
        self.comment = comment
        self.segment = segment
    }
}

// Recognition, validation, and rendering share this list of supported tokens.
private enum PromptPlaceholder: String, CaseIterable {
    case from, to, text, context
    case contextBlock = "context_block"
    case filename, format
    case stringKey = "string_key"
    case comment, segment
}

struct PromptRenderer {
    func resolvePresetTemplates(
        preset: PresetDefinition,
        cwd: URL
    ) throws -> (systemPrompt: String, userPrompt: String) {
        let systemTemplate = try resolveTemplate(
            inlineOrFile: nil,
            presetInline: preset.systemPrompt,
            presetFile: preset.systemPromptFile,
            cwd: cwd,
            promptLabel: "system"
        )

        let userTemplate = try resolveTemplate(
            inlineOrFile: nil,
            presetInline: preset.userPrompt,
            presetFile: preset.userPromptFile,
            cwd: cwd,
            promptLabel: "user"
        )

        return (systemTemplate, userTemplate)
    }

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

        guard !userTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidArguments("User prompt must not be empty. Provide a non-empty --user-prompt or preset user_prompt template.")
        }

        let systemTokens = tokens(in: systemTemplate)
        let userTokens = tokens(in: userTemplate)
        let tokenNames = (systemTokens + userTokens).map(\.name)
        guard tokenNames.contains(PromptPlaceholder.text.rawValue) else {
            throw AppError.invalidArguments("Prompt templates must contain {text} in the system or user prompt so the source text is sent. Add {text} to --system-prompt, --user-prompt, or the preset templates.")
        }

        let builtIns = BuiltInPresetStore.all()
        let fallback = builtIns[preset.name] ?? builtIns[BuiltInDefaults.preset]
        let customPromptActive = systemTemplate != (fallback?.systemPrompt ?? "") ||
            userTemplate != (fallback?.userPrompt ?? "")

        var warnings: [String] = []
        var warnedTokens: Set<String> = []
        for name in tokenNames where PromptPlaceholder(rawValue: name) == nil {
            if warnedTokens.insert(name).inserted {
                warnings.append("Warning: Unsupported prompt placeholder {\(name)} will be preserved literally. Use a supported placeholder or remove it from the template.")
            }
        }
        if noLang && !customPromptActive {
            warnings.append("Warning: --no-lang has no effect when using default prompts.")
        }

        if customPromptActive && !noLang {
            if !tokenNames.contains(PromptPlaceholder.from.rawValue) && !tokenNames.contains(PromptPlaceholder.to.rawValue) {
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

    private func placeholders(for context: PromptRenderContext) -> [PromptPlaceholder: String] {
        let trimmedContext = context.context.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            .from: context.from.isAuto ? BuiltInDefaults.sourceLanguagePlaceholder : context.from.displayName,
            .to: context.to.displayName,
            .text: context.text,
            .context: trimmedContext,
            .contextBlock: trimmedContext.isEmpty ? "" : "\nAdditional context: \(trimmedContext)",
            .filename: context.filename,
            .format: context.format.promptValue,
            .stringKey: context.stringKey,
            .comment: context.comment,
            .segment: context.segment,
        ]
    }

    private struct TemplateToken {
        let range: Range<String.Index>
        let name: String
    }

    private func tokens(in template: String) -> [TemplateToken] {
        // Only complete, identifier-shaped braces are tokens. JSON objects and
        // CSS declarations remain ordinary text, as do double-braced literals.
        let regex = Self.tokenPattern
        return regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).compactMap { match in
            guard let range = Range(match.range, in: template),
                  let nameRange = Range(match.range(at: 1), in: template) else { return nil }
            return TemplateToken(range: range, name: String(template[nameRange]))
        }
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: #"(?<!\{)\{([A-Za-z_][A-Za-z0-9_]*)\}(?!\})"#)

    private func substitute(_ template: String, placeholders: [PromptPlaceholder: String]) -> String {
        var output = ""
        var cursor = template.startIndex
        for token in tokens(in: template) {
            output += template[cursor..<token.range.lowerBound]
            if let placeholder = PromptPlaceholder(rawValue: token.name), let value = placeholders[placeholder] {
                output += value
            } else {
                output += template[token.range]
            }
            cursor = token.range.upperBound
        }
        output += template[cursor...]
        return output
    }
}
