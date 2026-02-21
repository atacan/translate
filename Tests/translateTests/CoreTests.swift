import XCTest
import TOMLKit
@testable import translate

final class CoreTests: XCTestCase {
    func testConfigDotSetGetUnsetWorksForNestedPaths() {
        let table = TOMLTable()

        ConfigKeyPath.set(table: table, key: "providers.openai-compatible.lm-studio.base_url", value: "http://localhost:1234/v1")
        XCTAssertEqual(
            ConfigKeyPath.get(table: table, key: "providers.openai-compatible.lm-studio.base_url")?.string,
            "http://localhost:1234/v1"
        )

        XCTAssertTrue(ConfigKeyPath.unset(table: table, key: "providers.openai-compatible.lm-studio.base_url"))
        XCTAssertNil(ConfigKeyPath.get(table: table, key: "providers.openai-compatible.lm-studio.base_url"))
    }

    func testOutputPlannerUsesPerFileOutputForSingleGlobMatch() throws {
        let file = ResolvedInputFile(path: URL(fileURLWithPath: "/tmp/example.md"), matchedByGlob: true)
        let mode = try OutputPlanner().plan(
            OutputPlanningRequest(
                inputMode: .files([file], cameFromGlob: true),
                toLanguage: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false),
                outputPath: nil,
                inPlace: false,
                suffix: nil,
                cwd: URL(fileURLWithPath: "/tmp")
            )
        ).mode

        switch mode {
        case .perFile(let targets, let inPlace):
            XCTAssertEqual(targets.count, 1)
            XCTAssertFalse(inPlace)
            XCTAssertEqual(targets[0].destination.lastPathComponent, "example_FR.md")
        default:
            XCTFail("Expected per-file output mode")
        }
    }

    func testPromptRendererSubstitutesContextBlock() throws {
        let renderer = PromptRenderer()
        let preset = PresetDefinition(
            name: "test",
            source: .userDefined,
            description: nil,
            systemPrompt: "Translate {from} to {to}",
            systemPromptFile: nil,
            userPrompt: "Body:{context_block}\n{text}",
            userPromptFile: nil,
            provider: nil,
            model: nil,
            from: nil,
            to: nil,
            format: nil
        )

        let templates = try renderer.resolvePrompts(
            preset: preset,
            systemPromptOverride: nil,
            userPromptOverride: nil,
            cwd: URL(fileURLWithPath: "/tmp"),
            noLang: false
        ).0

        let rendered = renderer.render(
            templates,
            with: PromptRenderContext(
                text: "hello",
                from: NormalizedLanguage(input: "auto", displayName: BuiltInDefaults.sourceLanguagePlaceholder, providerCode: "auto", isAuto: true),
                to: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false),
                context: "tooltip",
                filename: "",
                format: .text
            )
        )

        XCTAssertTrue(rendered.systemPrompt.contains("the source language"))
        XCTAssertTrue(rendered.systemPrompt.contains("French"))
        XCTAssertTrue(rendered.userPrompt.contains("Additional context: tooltip"))
    }

    func testFenceStrippingOnlyRemovesOutermostWrappingFence() {
        let wrapped = """
        ```markdown
        bonjour
        ```
        """
        let plain = ResponseSanitizer.stripWrappingCodeFence(wrapped)
        XCTAssertTrue(plain.stripped)
        XCTAssertEqual(plain.text, "bonjour")

        let mixed = "prefix\n```\nbonjour\n```"
        let untouched = ResponseSanitizer.stripWrappingCodeFence(mixed)
        XCTAssertFalse(untouched.stripped)
        XCTAssertEqual(untouched.text, mixed)
    }

    func testLanguageNormalizerRejectsAutoForTarget() {
        XCTAssertThrowsError(try LanguageNormalizer.normalizeTo("auto"))
    }
}
