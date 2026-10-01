import XCTest
import TOMLKit
import CatalogTranslation
import StringCatalog
@testable import translate

final class CatalogPromptTests: XCTestCase {
    private let network = NetworkRuntimeConfig(timeoutSeconds: 120, retries: 0, retryBaseDelaySeconds: 1)

    func testCatalogRequestsUseResolvedPresetAndCLIFieldsIndependently() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let file = try makeCatalog(in: directory)
        let table = TOMLTable()
        ConfigKeyPath.set(table: table, key: "presets.xcode-strings.system_prompt_file", value: "system.txt")
        ConfigKeyPath.set(table: table, key: "presets.xcode-strings.user_prompt_file", value: "user.txt")
        try "FILE SYSTEM {from}/{to} {filename} {string_key} {segment} {comment}".write(to: directory.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
        try "FILE USER {context_block} {text}".write(to: directory.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)
        try "CLI FILE {text} {context} {format}".write(to: directory.appendingPathComponent("override.txt"), atomically: true, encoding: .utf8)
        let config = ConfigResolver().resolve(path: directory.appendingPathComponent("config.toml"), table: table)
        let preset = try PresetResolver().resolvePreset(named: "xcode-strings", config: config)
        let plan = try await CatalogPendingPlan.prepare(file: file, targetLanguage: LanguageNormalizer.normalizeTo("fr"), jobs: 2)
        XCTAssertEqual(plan.requests.count, 3)

        for (systemOverride, userOverride, expectedSystem, expectedUser) in [
            (nil, nil, "FILE SYSTEM English/French", "FILE USER"),
            ("INLINE SYSTEM {from}/{to}", nil, "INLINE SYSTEM English/French", "FILE USER"),
            (nil, "@override.txt", "FILE SYSTEM English/French", "CLI FILE"),
            ("@system.txt", "INLINE USER {text} {context}", "FILE SYSTEM English/French", "INLINE USER")
        ] {
            let templates = try PromptRenderer().resolvePrompts(
                preset: preset, systemPromptOverride: systemOverride, userPromptOverride: userOverride,
                cwd: directory, noLang: false
            ).0
            let recorder = RequestRecorder()
            let provider = MockTranslationProvider { request in
                await recorder.append(request)
                return ProviderResult(text: "TR:\(request.text)", usage: nil, statusCode: 200, headers: [:])
            }
            let promptConfiguration = CatalogPromptConfiguration(
                templates: templates, context: "  Settings {to}  ", filename: file.path.lastPathComponent, format: .markdown
            )
            let result = try await plan.translate(using: CatalogBridge.makeTranslator(provider: provider, prompts: promptConfiguration, network: network), jobs: 2)
            XCTAssertTrue(result.report.failures.isEmpty)
            let requests = await recorder.requests
            XCTAssertEqual(requests.count, 3)
            for request in requests {
                XCTAssertEqual(request.from.providerCode, "en")
                XCTAssertEqual(request.to.providerCode, "fr")
                XCTAssertTrue(request.systemPrompt?.hasPrefix(expectedSystem) == true)
                XCTAssertTrue(request.userPrompt?.hasPrefix(expectedUser) == true)
                XCTAssertTrue(request.userPrompt?.contains("CLI context: Settings {to}") == true)
                XCTAssertTrue(request.userPrompt?.contains("Developer comment: Greeting {from}") == true)
                XCTAssertTrue(request.userPrompt?.contains(request.text) == true)
                XCTAssertFalse(request.userPrompt?.contains("Settings French") == true)
            }
            if systemOverride == nil {
                XCTAssertTrue(requests.allSatisfy { $0.systemPrompt?.contains("Localizable.xcstrings greeting string") == true })
                XCTAssertTrue(requests.contains { $0.systemPrompt?.contains("stringUnit") == true })
                XCTAssertTrue(requests.contains { $0.systemPrompt?.contains("stringSet[0]") == true })
                XCTAssertTrue(requests.allSatisfy { $0.systemPrompt?.contains("Greeting {from}") == true })
            }
        }
    }

    func testInlineUserPresetShadowsFileAndBuiltInFallbackIsPerField() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let file = try makeCatalog(in: directory)
        for name in ["xcode-strings", "custom"] {
            let table = TOMLTable()
            ConfigKeyPath.set(table: table, key: "presets.\(name).user_prompt", value: "CUSTOM {to}: {text}")
            ConfigKeyPath.set(table: table, key: "presets.\(name).user_prompt_file", value: "missing.txt")
            let config = ConfigResolver().resolve(path: directory.appendingPathComponent("config.toml"), table: table)
            let preset = try PresetResolver().resolvePreset(named: name, config: config)
            let templates = try PromptRenderer().resolvePrompts(preset: preset, systemPromptOverride: nil, userPromptOverride: nil, cwd: directory, noLang: false).0
            let plan = try await CatalogPendingPlan.prepare(file: file, targetLanguage: LanguageNormalizer.normalizeTo("fr"), jobs: 1)
            let recorder = RequestRecorder()
            let provider = MockTranslationProvider { request in
                await recorder.append(request)
                return ProviderResult(text: request.text, usage: nil, statusCode: 200, headers: [:])
            }
            _ = try await plan.translate(using: CatalogBridge.makeTranslator(provider: provider, prompts: CatalogPromptConfiguration(templates: templates, context: "", filename: "Localizable.xcstrings", format: .text), network: network), jobs: 1)
            let requests = await recorder.requests
            XCTAssertTrue(requests.allSatisfy { $0.userPrompt == "CUSTOM French: \($0.text)" })
            XCTAssertTrue(requests.allSatisfy { $0.systemPrompt?.contains(name == "xcode-strings" ? "Xcode string catalog" : "original meaning, tone") == true })
        }
    }

    func testCatalogDefaultOnlyAppliesWithoutExplicitOrCustomizedDefault() {
        let resolver = PresetResolver()
        let table = TOMLTable()
        func config() -> ResolvedConfig { ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table) }
        XCTAssertEqual(resolver.activePresetName(cliPreset: nil, config: config(), isCatalog: true), "xcode-strings")
        XCTAssertEqual(resolver.activePresetName(cliPreset: nil, config: config()), "general")
        XCTAssertEqual(resolver.activePresetName(cliPreset: "general", config: config(), isCatalog: true), "general")
        ConfigKeyPath.set(table: table, key: "defaults.preset", value: "general")
        XCTAssertEqual(resolver.activePresetName(cliPreset: nil, config: config(), isCatalog: true), "general")
        _ = ConfigKeyPath.unset(table: table, key: "defaults.preset")
        ConfigKeyPath.set(table: table, key: "presets.general.model", value: "custom-model")
        XCTAssertEqual(resolver.activePresetName(cliPreset: nil, config: config(), isCatalog: true), "general")
    }

    private func makeCatalog(in directory: URL) throws -> ResolvedInputFile {
        let url = directory.appendingPathComponent("Localizable.xcstrings")
        let catalog = StringCatalog(sourceLanguage: "en", strings: [
            "greeting": StringEntry(comment: "Greeting {from}", localizations: [
                "en": StringLocalization(stringUnit: StringUnit(state: .translated, value: "Hello single"), stringSet: StringSet(state: .translated, values: ["Hello {to}", "```Hello %@```"]))
            ])
        ], version: "1.0")
        try catalog.encodePrettyToString().write(to: url, atomically: true, encoding: .utf8)
        return ResolvedInputFile(path: url, matchedByGlob: false)
    }
}

private actor RequestRecorder {
    private(set) var requests: [ProviderRequest] = []
    func append(_ request: ProviderRequest) { requests.append(request) }
}
