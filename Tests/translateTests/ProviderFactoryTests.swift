import XCTest
import TOMLKit
@testable import translate

final class ProviderFactoryTests: XCTestCase {
    func testOpenAIResolvesWithAPIKey() throws {
        let factory = ProviderFactory(config: makeConfig(), env: ["OPENAI_API_KEY": "key"])
        let selection = try factory.make(
            providerName: ProviderID.openai.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: nil,
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .openai)
        XCTAssertEqual(selection.name, ProviderID.openai.rawValue)
        XCTAssertFalse(selection.promptless)
        XCTAssertEqual(selection.apiKey, "key")
    }

    func testAnthropicResolvesWithAPIKey() throws {
        let factory = ProviderFactory(config: makeConfig(), env: ["ANTHROPIC_API_KEY": "key"])
        let selection = try factory.make(
            providerName: ProviderID.anthropic.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: nil,
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .anthropic)
        XCTAssertEqual(selection.name, ProviderID.anthropic.rawValue)
    }

    func testGeminiResolvesWithAPIKey() throws {
        let factory = ProviderFactory(config: makeConfig(), env: ["GEMINI_API_KEY": "key"])
        let selection = try factory.make(
            providerName: ProviderID.gemini.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: nil,
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .gemini)
        XCTAssertEqual(selection.name, ProviderID.gemini.rawValue)
        XCTAssertEqual(selection.apiKey, "key")
    }

    func testOpenResponsesResolvesWithAPIKey() throws {
        let factory = ProviderFactory(config: makeConfig(), env: ["OPEN_RESPONSES_API_KEY": "key"])
        let selection = try factory.make(
            providerName: ProviderID.openResponses.rawValue,
            modelOverride: nil,
            baseURLOverride: "https://openrouter.ai/api/v1",
            apiKeyOverride: nil,
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .openResponses)
        XCTAssertEqual(selection.name, ProviderID.openResponses.rawValue)
        XCTAssertEqual(selection.baseURL, "https://openrouter.ai/api/v1")
    }

    func testOllamaResolvesWithoutAPIKey() throws {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        let selection = try factory.make(
            providerName: ProviderID.ollama.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: nil,
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .ollama)
        XCTAssertNil(selection.apiKey)
    }

    func testMLXResolvesWithoutAPIKey() throws {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        let selection = try factory.make(
            providerName: ProviderID.mlx.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: nil,
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .mlx)
        XCTAssertNotNil(selection.model)
    }

    func testCoreMLRequiresModelPath() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.coreml.rawValue,
                modelOverride: nil,
                baseURLOverride: nil,
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.message, "--model is required when using coreml (path to .mlmodelc).")
        }
    }

    func testLlamaRequiresModelPath() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.llama.rawValue,
                modelOverride: nil,
                baseURLOverride: nil,
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.message, "--model is required when using llama (path to .gguf).")
        }
    }

    func testOpenAICompatibleRequiresAPIKey() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.openAICompatible.rawValue,
                modelOverride: "model-x",
                baseURLOverride: "http://localhost:1234/v1",
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.message, "Error: API key is required for provider 'openai-compatible'.")
            XCTAssertEqual(appError.exitCode, .runtimeError)
        }
    }

    func testNamedOpenAICompatibleRequiresAPIKey() {
        let config = makeConfig(
            namedOpenAICompatible: [
                "lmstudio": ProviderConfigEntry(baseURL: "http://localhost:1234/v1", model: "llama3", apiKey: nil),
            ]
        )
        let factory = ProviderFactory(config: config, env: [:])

        XCTAssertThrowsError(
            try factory.make(
                providerName: "lmstudio",
                modelOverride: nil,
                baseURLOverride: nil,
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.message, "Error: API key is required for provider 'openai-compatible'.")
        }
    }

    func testAppleTranslateRejectsModelOverride() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.appleTranslate.rawValue,
                modelOverride: "model-x",
                baseURLOverride: nil,
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(
                appError.message,
                "--model is not applicable for apple-translate. This provider does not use a model."
            )
            XCTAssertEqual(appError.exitCode, .invalidArguments)
        }
    }

    func testAppleIntelligenceRejectsAPIKey() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.appleIntelligence.rawValue,
                modelOverride: nil,
                baseURLOverride: nil,
                apiKeyOverride: "secret",
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.message, "--api-key is not applicable for apple-intelligence.")
            XCTAssertEqual(appError.exitCode, .invalidArguments)
        }
    }

    func testAppleTranslateRejectsBaseURL() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.appleTranslate.rawValue,
                modelOverride: nil,
                baseURLOverride: "http://localhost:1234",
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(
                appError.message,
                "--base-url cannot be used with --provider apple-translate. It is only valid for openai-compatible providers."
            )
        }
    }

    func testDeepLRejectsModelOverride() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.deepl.rawValue,
                modelOverride: "model-x",
                baseURLOverride: nil,
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(
                appError.message,
                "--model is not applicable for deepl. This provider does not use a model."
            )
            XCTAssertEqual(appError.exitCode, .invalidArguments)
        }
    }

    func testDeepLRequiresAPIKey() {
        let factory = ProviderFactory(config: makeConfig(), env: [:])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.deepl.rawValue,
                modelOverride: nil,
                baseURLOverride: nil,
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.message, "Error: DEEPL_API_KEY is required for provider 'deepl'.")
            XCTAssertEqual(appError.exitCode, .runtimeError)
        }
    }

    func testDeepLUsesCLIAPIKeyPrecedence() throws {
        let config = makeConfig(
            providers: [
                ProviderID.deepl.rawValue: ProviderConfigEntry(baseURL: nil, model: nil, apiKey: "config-key"),
            ]
        )
        let factory = ProviderFactory(config: config, env: ["DEEPL_API_KEY": "env-key"])

        let selection = try factory.make(
            providerName: ProviderID.deepl.rawValue,
            modelOverride: nil,
            baseURLOverride: nil,
            apiKeyOverride: "cli-key",
            explicitProvider: true
        )

        XCTAssertEqual(selection.provider.id, .deepl)
        XCTAssertEqual(selection.apiKey, "cli-key")
        XCTAssertTrue(selection.promptless)
        XCTAssertNil(selection.model)
    }

    func testDeepLRejectsBaseURL() {
        let factory = ProviderFactory(config: makeConfig(), env: ["DEEPL_API_KEY": "key"])
        XCTAssertThrowsError(
            try factory.make(
                providerName: ProviderID.deepl.rawValue,
                modelOverride: nil,
                baseURLOverride: "https://example.com",
                apiKeyOverride: nil,
                explicitProvider: true
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(
                appError.message,
                "--base-url cannot be used with --provider deepl. It is only valid for openai-compatible providers."
            )
        }
    }

    private func makeConfig(
        providers: [String: ProviderConfigEntry] = [:],
        namedOpenAICompatible: [String: ProviderConfigEntry] = [:]
    ) -> ResolvedConfig {
        ResolvedConfig(
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
            providers: providers,
            namedOpenAICompatible: namedOpenAICompatible,
            presets: [:]
        )
    }
}
