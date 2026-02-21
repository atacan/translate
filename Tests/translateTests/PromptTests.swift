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
}
