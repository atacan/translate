import Foundation

enum BuiltInPresetStore {
    static func all() -> [String: PresetDefinition] {
        [
            "general": PresetDefinition(
                name: "general",
                source: .builtIn,
                description: "General-purpose translation",
                systemPrompt: """
                You are a skilled translator with expertise in translating {from} to {to}, preserving the original meaning, tone, and nuance.
                Maintain any formatting present in the source text.
                Only output the translation. Do not include explanations, commentary, or original text.
                Do not wrap your output in backticks or code blocks.
                """,
                systemPromptFile: nil,
                userPrompt: """
                Translate the following {format} from {from} to {to}.{context_block}

                <source_text>
                {text}
                </source_text>
                """,
                userPromptFile: nil,
                provider: nil,
                model: nil,
                from: nil,
                to: nil,
                format: nil
            ),
            "markdown": PresetDefinition(
                name: "markdown",
                source: .builtIn,
                description: "Preserves markdown formatting",
                systemPrompt: """
                You are a skilled translator with extensive experience in translating {from} text to {to} while maintaining all markdown formatting.
                Preserve heading levels (e.g. # for H1, ## for H2), bullet points, numbered lists, bold (**text**), italics (*text*), inline code (`code`), code blocks, links, and line breaks exactly as in the source.
                Do not translate URLs, href destinations, anchor link targets, image src values, code content, frontmatter keys, or other technical identifiers.
                Do not wrap your output in backticks or a code block.
                """,
                systemPromptFile: nil,
                userPrompt: """
                Translate the following markdown from {from} to {to}.{context_block}

                <source_text>
                {text}
                </source_text>
                """,
                userPromptFile: nil,
                provider: nil,
                model: nil,
                from: nil,
                to: nil,
                format: nil
            ),
            "xcode-strings": PresetDefinition(
                name: "xcode-strings",
                source: .builtIn,
                description: "Xcode string catalogs with format specifiers",
                systemPrompt: """
                You are a skilled translator with extensive experience in translating {from} UI text to {to} for macOS and iOS applications.
                The text was taken from an Xcode string catalog (.xcstrings).
                Preserve all format specifiers such as %@, %lld, %.2f, %1$@, %2$@, %3$@, %1$lld, %2$lld and similar placeholders. Place them at the contextually appropriate position in the translated string.
                If there is markdown formatting, keep it intact.
                Preserve the meaning and tone appropriate for a macOS/iOS user interface.
                If multiple valid translations exist, use the context provided to choose the most natural and idiomatic option for a native {to} speaker.
                Only output the translation. Do not include explanations, original text, or wrapping backticks.
                """,
                systemPromptFile: nil,
                userPrompt: """
                Translate the following {from} UI string to {to}.{context_block}

                <source_text>
                {text}
                </source_text>
                """,
                userPromptFile: nil,
                provider: nil,
                model: nil,
                from: nil,
                to: nil,
                format: nil
            ),
            "legal": PresetDefinition(
                name: "legal",
                source: .builtIn,
                description: "Formal, strict fidelity",
                systemPrompt: """
                You are a professional legal translator with expertise in translating legal and formal documents from {from} to {to}.
                Your translation must be faithful to the source: do not paraphrase, simplify, omit, or add content.
                Preserve the formal register, legal terminology, and document structure.
                Only output the translated text. Do not include explanations, commentary, or wrapping backticks.
                """,
                systemPromptFile: nil,
                userPrompt: """
                Translate the following legal text from {from} to {to}.{context_block}

                <source_text>
                {text}
                </source_text>
                """,
                userPromptFile: nil,
                provider: nil,
                model: nil,
                from: nil,
                to: nil,
                format: nil
            ),
            "ui": PresetDefinition(
                name: "ui",
                source: .builtIn,
                description: "Short UI strings, button labels",
                systemPrompt: """
                You are a translator specializing in software UI copy. Translate {from} text to {to}.
                Output concise, natural translations appropriate for buttons, labels, menu items, tooltips, and other interface elements.
                Use standard UI conventions and terminology for {to}-speaking users of macOS and iOS.
                Only output the translated string. Do not include backticks, quotation marks, or explanation.
                """,
                systemPromptFile: nil,
                userPrompt: """
                Translate the following UI string from {from} to {to}.{context_block}

                <source_text>
                {text}
                </source_text>
                """,
                userPromptFile: nil,
                provider: nil,
                model: nil,
                from: nil,
                to: nil,
                format: nil
            ),
        ]
    }
}
