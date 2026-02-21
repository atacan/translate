import XCTest
import TOMLKit
@testable import translate

final class SpecAssertionTests: XCTestCase {
    func testUserDefinedPresetFallsBackToGeneralPromptTemplates() throws {
        let config = ResolvedConfig(
            path: URL(fileURLWithPath: "/tmp/config.toml"),
            table: TOMLTable(),
            defaultsProvider: "openai",
            defaultsFrom: "auto",
            defaultsTo: "en",
            defaultsPreset: "general",
            defaultsFormat: .auto,
            defaultsYes: false,
            defaultsJobs: 1,
            network: NetworkRuntimeConfig(timeoutSeconds: 120, retries: 3, retryBaseDelaySeconds: 1),
            providers: [:],
            namedOpenAICompatible: [:],
            presets: [
                "custom": PresetDefinition(
                    name: "custom",
                    source: .userDefined,
                    description: nil,
                    systemPrompt: nil,
                    systemPromptFile: nil,
                    userPrompt: nil,
                    userPromptFile: nil,
                    provider: "ollama",
                    model: nil,
                    from: nil,
                    to: nil,
                    format: nil
                ),
            ]
        )

        let resolved = try PresetResolver().resolvePreset(named: "custom", config: config)
        XCTAssertEqual(resolved.provider, "ollama")
        XCTAssertFalse((resolved.systemPrompt ?? "").isEmpty)
        XCTAssertFalse((resolved.userPrompt ?? "").isEmpty)
    }

    func testPromptRendererResolvesPresetPromptFiles() throws {
        let temp = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let systemFile = temp.appendingPathComponent("system.txt")
        let userFile = temp.appendingPathComponent("user.txt")
        try "System {from}->{to}".write(to: systemFile, atomically: true, encoding: .utf8)
        try "User {text}".write(to: userFile, atomically: true, encoding: .utf8)

        let preset = PresetDefinition(
            name: "from-files",
            source: .userDefined,
            description: nil,
            systemPrompt: nil,
            systemPromptFile: systemFile.path,
            userPrompt: nil,
            userPromptFile: userFile.path,
            provider: nil,
            model: nil,
            from: nil,
            to: nil,
            format: nil
        )

        let templates = try PromptRenderer().resolvePresetTemplates(preset: preset, cwd: temp)
        XCTAssertEqual(templates.systemPrompt, "System {from}->{to}")
        XCTAssertEqual(templates.userPrompt, "User {text}")
    }

    func testPresetResolverKeepsPromptFilesWhenFallingBackToGeneral() throws {
        let temp = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let systemFile = temp.appendingPathComponent("system.txt")
        let userFile = temp.appendingPathComponent("user.txt")
        try "FILE SYSTEM {from}->{to}".write(to: systemFile, atomically: true, encoding: .utf8)
        try "FILE USER {text}".write(to: userFile, atomically: true, encoding: .utf8)

        let config = ResolvedConfig(
            path: URL(fileURLWithPath: "/tmp/config.toml"),
            table: TOMLTable(),
            defaultsProvider: "openai",
            defaultsFrom: "auto",
            defaultsTo: "en",
            defaultsPreset: "general",
            defaultsFormat: .auto,
            defaultsYes: false,
            defaultsJobs: 1,
            network: NetworkRuntimeConfig(timeoutSeconds: 120, retries: 3, retryBaseDelaySeconds: 1),
            providers: [:],
            namedOpenAICompatible: [:],
            presets: [
                "files-only": PresetDefinition(
                    name: "files-only",
                    source: .userDefined,
                    description: nil,
                    systemPrompt: nil,
                    systemPromptFile: systemFile.path,
                    userPrompt: nil,
                    userPromptFile: userFile.path,
                    provider: nil,
                    model: nil,
                    from: nil,
                    to: nil,
                    format: nil
                ),
            ]
        )

        let resolved = try PresetResolver().resolvePreset(named: "files-only", config: config)
        let templates = try PromptRenderer().resolvePresetTemplates(preset: resolved, cwd: temp)
        XCTAssertEqual(templates.systemPrompt, "FILE SYSTEM {from}->{to}")
        XCTAssertEqual(templates.userPrompt, "FILE USER {text}")
    }

    func testProviderFactoryAllowsMissingCredentialsWhenValidationDisabled() throws {
        let config = ResolvedConfig(
            path: URL(fileURLWithPath: "/tmp/config.toml"),
            table: TOMLTable(),
            defaultsProvider: "openai",
            defaultsFrom: "auto",
            defaultsTo: "en",
            defaultsPreset: "general",
            defaultsFormat: .auto,
            defaultsYes: false,
            defaultsJobs: 1,
            network: NetworkRuntimeConfig(timeoutSeconds: 120, retries: 3, retryBaseDelaySeconds: 1),
            providers: [:],
            namedOpenAICompatible: [:],
            presets: [:]
        )

        let selection = try ProviderFactory(config: config, env: [:]).make(
            providerName: ProviderID.openai.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: nil,
            explicitProvider: true,
            requireCredentials: false
        )

        XCTAssertEqual(selection.name, ProviderID.openai.rawValue)
        XCTAssertNil(selection.apiKey)
    }

    func testOutputWriterSkipsOverwritePromptWhenConfigured() throws {
        let temp = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let destination = temp.appendingPathComponent("output.txt")
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let terminal = TerminalIO(quiet: true, verbose: false)
        let writer = OutputWriter(
            terminal: terminal,
            prompter: ConfirmationPrompter(terminal: terminal, assumeYes: false),
            skipOverwriteConfirmation: true
        )

        XCTAssertNoThrow(try writer.writeFile(text: "new", destination: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new")
    }

    func testFormatDetectorUsesExplicitHintWithoutFile() {
        XCTAssertEqual(FormatDetector.detect(formatHint: .markdown, inputFile: nil), .markdown)
        XCTAssertEqual(FormatDetector.detect(formatHint: .html, inputFile: nil), .html)
    }
}
