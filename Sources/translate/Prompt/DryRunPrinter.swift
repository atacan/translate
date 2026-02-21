import Foundation

enum DryRunPrinter {
    static func render(
        provider: String,
        model: String?,
        from: NormalizedLanguage,
        to: NormalizedLanguage,
        prompts: ResolvedPromptSet,
        inputText: String
    ) -> String {
        let preview = inputText.count > 500 ? String(inputText.prefix(500)) + "..." : inputText
        let sourceLangLabel = from.isAuto
            ? "\(BuiltInDefaults.sourceLanguagePlaceholder) (auto-detect)"
            : from.displayName

        return """
        === DRY RUN ===

        Provider:       \(provider)
        Model:          \(model ?? "(provider default)")
        Source lang:    \(sourceLangLabel)
        Target lang:    \(to.displayName)

        --- SYSTEM PROMPT ---
        \(prompts.systemPrompt)

        --- USER PROMPT ---
        \(prompts.userPrompt)

        --- INPUT (first 500 chars) ---
        \(preview)
        """
    }
}
