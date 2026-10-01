import XCTest
import TOMLKit
@testable import translate

final class PromptTests: XCTestCase {
    func testCustomPromptWarnsWhenLanguagePlaceholdersMissing() throws {
        let renderer = PromptRenderer()
        let preset = PresetDefinition(
            name: "custom",
            source: .userDefined,
            description: nil,
            systemPrompt: "Translate faithfully.",
            systemPromptFile: nil,
            userPrompt: "Text: {text}",
            userPromptFile: nil,
            provider: nil,
            model: nil,
            from: nil,
            to: nil,
            format: nil
        )

        let (_, warnings) = try renderer.resolvePrompts(
            preset: preset,
            systemPromptOverride: nil,
            userPromptOverride: nil,
            cwd: URL(fileURLWithPath: "/tmp"),
            noLang: false
        )

        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(
            warnings.first,
            "Warning: Your custom prompt does not contain {from} or {to} placeholders. If you have hardcoded languages, pass --no-lang to suppress this warning."
        )
    }

    func testNoLangWarningSuppressedForCustomPrompt() throws {
        let renderer = PromptRenderer()
        let preset = PresetDefinition(
            name: "custom",
            source: .userDefined,
            description: nil,
            systemPrompt: "Translate faithfully.",
            systemPromptFile: nil,
            userPrompt: "Text: {text}",
            userPromptFile: nil,
            provider: nil,
            model: nil,
            from: nil,
            to: nil,
            format: nil
        )

        let (_, warnings) = try renderer.resolvePrompts(
            preset: preset,
            systemPromptOverride: nil,
            userPromptOverride: nil,
            cwd: URL(fileURLWithPath: "/tmp"),
            noLang: true
        )

        XCTAssertTrue(warnings.isEmpty)
    }

    func testNoLangWarnsWhenUsingDefaultPrompt() throws {
        let renderer = PromptRenderer()
        let preset = try PresetResolver().resolvePreset(
            named: "general",
            config: ResolvedConfig(
                path: URL(fileURLWithPath: "/tmp/config.toml"),
                table: .init(),
                defaultsProvider: "openai",
                defaultsFrom: "auto",
                defaultsTo: "en",
                defaultsPreset: "general",
                defaultsFormat: .auto,
                defaultsStream: false,
                defaultsYes: false,
                defaultsJobs: 1,
                network: NetworkRuntimeConfig(timeoutSeconds: 120, retries: 3, retryBaseDelaySeconds: 1),
                providers: [:],
                namedOpenAICompatible: [:],
                presets: [:]
            )
        )

        let (_, warnings) = try renderer.resolvePrompts(
            preset: preset,
            systemPromptOverride: nil,
            userPromptOverride: nil,
            cwd: URL(fileURLWithPath: "/tmp"),
            noLang: true
        )

        XCTAssertEqual(warnings, ["Warning: --no-lang has no effect when using default prompts."])
    }

    func testRenderingPreservesInsertedTokensDeterministically() throws {
        let renderer = PromptRenderer()
        let templates = try resolve(
            preset: preset(system: "{from} → {to}; {text}; {context}; {filename}",
                           user: "{text}|{context_block}|{context}|{filename}|{format}")
        ).0
        let source = "🔑 Keep literal {to}, {context}, {filename}, {text}, and {unknown}"
        let context = "Do not change {text}, {to}, or {context_block}"
        let renderContext = PromptRenderContext(
            text: source,
            from: try LanguageNormalizer.normalizeFrom("auto"),
            to: try LanguageNormalizer.normalizeTo("fr"),
            context: " \n\(context)\t ",
            filename: "{text}-{to}.md",
            format: .markdown
        )

        for _ in 0..<100 {
            let rendered = renderer.render(templates, with: renderContext)
            XCTAssertEqual(rendered.systemPrompt, "the source language → French; \(source); \(context); {text}-{to}.md")
            XCTAssertEqual(rendered.userPrompt, "\(source)|\nAdditional context: \(context)|\(context)|{text}-{to}.md|markdown")
        }
    }

    func testCatalogTokensAreRecognizedAndPreserveInsertedValues() throws {
        let (templates, warnings) = try resolve(
            preset: preset(system: "{to}", user: "{text}|{string_key}|{comment}|{segment}")
        )
        XCTAssertTrue(warnings.isEmpty)
        let context = PromptRenderContext(
            text: "Hello", from: try LanguageNormalizer.normalizeFrom("en"),
            to: try LanguageNormalizer.normalizeTo("fr"), context: "", filename: "", format: .text,
            stringKey: "key.{to}", comment: "Keep {text}", segment: "plural.other {comment}"
        )
        XCTAssertEqual(PromptRenderer().render(templates, with: context).userPrompt,
                       "Hello|key.{to}|Keep {text}|plural.other {comment}")

        let plainContext = PromptRenderContext(
            text: "Hello", from: context.from, to: context.to, context: " \t\n", filename: "", format: .text
        )
        XCTAssertEqual(PromptRenderer().render(templates, with: plainContext).userPrompt, "Hello|||")
    }

    func testRejectsEmptyUserTemplateEvenWhenSystemContainsSource() throws {
        for user in ["", " \n\t\r "] {
            XCTAssertThrowsError(try resolve(preset: preset(system: "{text} {to}", user: user))) { error in
                let appError = error as? AppError
                XCTAssertEqual(appError?.exitCode, .invalidArguments)
                XCTAssertTrue(appError?.message.contains("User prompt must not be empty") == true)
                XCTAssertTrue(appError?.message.contains("--user-prompt") == true)
            }
        }
    }

    func testRejectsTemplatesWithoutACompleteSourcePlaceholder() throws {
        for user in ["Translate to {to}", "{text", "text}", "{ text }", "{{text}}", "{text.more}"] {
            XCTAssertThrowsError(try resolve(preset: preset(system: "{from} to {to}", user: user))) { error in
                let appError = error as? AppError
                XCTAssertEqual(appError?.exitCode, .invalidArguments)
                XCTAssertTrue(appError?.message.contains("must contain {text}") == true)
            }
        }
    }

    func testSourceMayAppearOnlyInSystemTemplateAndSystemMayBeEmpty() throws {
        let (templates, warnings) = try resolve(preset: preset(system: "{to}: {text}", user: "Translate faithfully."))
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertEqual(templates.systemPrompt, "{to}: {text}")
        XCTAssertNoThrow(try resolve(preset: preset(system: "", user: "{to}: {text}")))
    }

    func testUnknownTemplateTokensWarnOnceInOrderAndRemainLiteral() throws {
        let system = #"JSON: {"key": "value"}; CSS: body { color: red; }; {} {{literal}} {unknown} {unknown}"#
        let user = "{text} {to} {other_2} {unknown} {broken {not-an-identifier}"
        let (templates, warnings) = try resolve(preset: preset(system: system, user: user), noLang: true)
        XCTAssertEqual(warnings, [
            "Warning: Unsupported prompt placeholder {unknown} will be preserved literally. Use a supported placeholder or remove it from the template.",
            "Warning: Unsupported prompt placeholder {other_2} will be preserved literally. Use a supported placeholder or remove it from the template.",
        ])
        let rendered = PromptRenderer().render(templates, with: PromptRenderContext(
            text: "{source_only}", from: try LanguageNormalizer.normalizeFrom("en"),
            to: try LanguageNormalizer.normalizeTo("fr"), context: "{context_only}", filename: "", format: .text
        ))
        XCTAssertEqual(rendered.systemPrompt, system)
        XCTAssertEqual(rendered.userPrompt, "{source_only} French {other_2} {unknown} {broken {not-an-identifier}")
    }

    func testRawPresetInspectionDoesNotRequireValidExecutionTemplates() throws {
        let templates = try PromptRenderer().resolvePresetTemplates(
            preset: preset(system: "Literal {unsupported}", user: ""), cwd: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(templates.systemPrompt, "Literal {unsupported}")
        XCTAssertEqual(templates.userPrompt, "")
    }

    func testNoLangDoesNotBypassSourceValidation() throws {
        XCTAssertThrowsError(try resolve(preset: preset(system: "French", user: "Translate this"), noLang: true))
    }

    func testMetadataOnlyUserPresetsKeepDefaultPromptClassification() throws {
        for name in ["general", "ui", "provider-only"] {
            let table = TOMLTable()
            let presets = TOMLTable()
            let metadata = TOMLTable()
            metadata["provider"] = "ollama"
            metadata["model"] = "custom-model"
            metadata["description"] = "Metadata override"
            metadata["from"] = "tr"
            metadata["to"] = "fr"
            metadata["format"] = "markdown"
            presets[name] = metadata
            table["presets"] = presets
            let config = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table)
            let resolvedPreset = try PresetResolver().resolvePreset(named: name, config: config)
            let (templates, warnings) = try resolve(preset: resolvedPreset, noLang: true)
            XCTAssertEqual(resolvedPreset.source, .userDefined)
            XCTAssertEqual(resolvedPreset.provider, "ollama")
            XCTAssertFalse(templates.customPromptActive, name)
            XCTAssertEqual(warnings, ["Warning: --no-lang has no effect when using default prompts."], name)
        }
    }

    func testIdenticalOverridesAreNotPromptCustomization() throws {
        let general = try XCTUnwrap(BuiltInPresetStore.all()["general"])
        let (templates, warnings) = try resolve(
            preset: general, systemOverride: general.systemPrompt, userOverride: general.userPrompt, noLang: true
        )
        XCTAssertFalse(templates.customPromptActive)
        XCTAssertEqual(warnings, ["Warning: --no-lang has no effect when using default prompts."])
    }

    func testInlinePresetFieldsTakePrecedenceOverUnusedFiles() throws {
        var custom = preset(system: "Inline {to}", user: "Inline {text}")
        custom.systemPromptFile = "missing-system.txt"
        custom.userPromptFile = "missing-user.txt"
        let (templates, _) = try resolve(preset: custom)
        XCTAssertEqual(templates.systemPrompt, "Inline {to}")
        XCTAssertEqual(templates.userPrompt, "Inline {text}")
        XCTAssertTrue(templates.customPromptActive)
    }

    func testCLIOverridesResolveFilesAndPreservePerFieldPresetPrecedence() throws {
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }
        try "FILE SYSTEM {to}".write(to: cwd.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
        try "FILE USER {text}".write(to: cwd.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)
        var custom = preset(system: "PRESET SYSTEM {to}", user: "PRESET USER {text}")
        custom.systemPromptFile = "missing-system.txt"
        custom.userPromptFile = "missing-user.txt"

        for (arguments, expectedSystem, expectedUser) in [
            (["--system-prompt", "@system.txt"], "FILE SYSTEM {to}", "PRESET USER {text}"),
            (["--user-prompt", "@user.txt"], "PRESET SYSTEM {to}", "FILE USER {text}"),
            (["--system-prompt", "CLI {to}", "--user-prompt", "CLI {text}"], "CLI {to}", "CLI {text}"),
        ] {
            let command = try XCTUnwrap(TranslateRunCommand.parseAsRoot(arguments + ["--text", "hello"]) as? TranslateRunCommand)
            let (templates, _) = try resolve(
                preset: custom, systemOverride: command.options.systemPrompt,
                userOverride: command.options.userPrompt, cwd: cwd
            )
            XCTAssertEqual(templates.systemPrompt, expectedSystem)
            XCTAssertEqual(templates.userPrompt, expectedUser)
        }

        custom.systemPrompt = nil
        custom.userPrompt = nil
        custom.systemPromptFile = "system.txt"
        custom.userPromptFile = "user.txt"
        let (templates, _) = try resolve(preset: custom, systemOverride: "CLI {to}", cwd: cwd)
        XCTAssertEqual(templates.systemPrompt, "CLI {to}")
        XCTAssertEqual(templates.userPrompt, "FILE USER {text}")
    }

    func testInvalidTemplateFilesFailAfterResolution() throws {
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }
        let userFile = cwd.appendingPathComponent("user.txt")
        for contents in [" \n\t", "Translate to {to} without source"] {
            try contents.write(to: userFile, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try resolve(preset: preset(system: "{to}", user: "{text}"), userOverride: "@user.txt", cwd: cwd)) { error in
                let appError = error as? AppError
                XCTAssertEqual(appError?.exitCode, .invalidArguments)
                XCTAssertTrue(appError?.message.contains(contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "User prompt must not be empty" : "must contain {text}") == true)
            }
        }
    }

    func testExecutionRejectsInvalidLLMPromptsBeforeRequests() async throws {
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }
        try "".write(to: cwd.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let command = try XCTUnwrap(TranslateRunCommand.parseAsRoot([
            "--config", cwd.appendingPathComponent("config.toml").path,
            "--provider", "ollama", "--text", "hello", "--system-prompt", "French",
            "--user-prompt", "Translate this", "--quiet",
        ]) as? TranslateRunCommand)
        do {
            try await TranslationOrchestrator().run(options: command.options, global: command.global)
            XCTFail("Invalid prompt should fail before contacting Ollama")
        } catch let error as AppError {
            XCTAssertEqual(error.exitCode, .invalidArguments)
            XCTAssertTrue(error.message.contains("must contain {text}"))
        }
    }

    func testPromptlessExecutionSkipsUnusedTemplateFilesAndValidation() async throws {
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }
        let config = cwd.appendingPathComponent("config.toml")
        try """
        [presets.invalid]
        system_prompt_file = "missing-system.txt"
        user_prompt = ""
        """.write(to: config, atomically: true, encoding: .utf8)
        let command = try XCTUnwrap(TranslateRunCommand.parseAsRoot([
            "--config", config.path, "--preset", "invalid", "--provider", "deepl",
            "--dry-run", "--text", "hello", "--user-prompt", "@missing-user.txt", "--quiet",
        ]) as? TranslateRunCommand)
        try await TranslationOrchestrator().run(options: command.options, global: command.global)
    }

    private func preset(system: String, user: String) -> PresetDefinition {
        PresetDefinition(name: "custom", source: .userDefined, description: nil,
                         systemPrompt: system, systemPromptFile: nil, userPrompt: user, userPromptFile: nil,
                         provider: nil, model: nil, from: nil, to: nil, format: nil)
    }

    private func resolve(
        preset: PresetDefinition,
        systemOverride: String? = nil,
        userOverride: String? = nil,
        cwd: URL = URL(fileURLWithPath: "/tmp"),
        noLang: Bool = false
    ) throws -> (ResolvedPromptSet, [String]) {
        try PromptRenderer().resolvePrompts(preset: preset, systemPromptOverride: systemOverride,
                                           userPromptOverride: userOverride, cwd: cwd, noLang: noLang)
    }
}
