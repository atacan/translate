import XCTest
import TOMLKit
@testable import translate

final class ProviderFactoryTests: XCTestCase {
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

    private func makeConfig(providers: [String: ProviderConfigEntry] = [:]) -> ResolvedConfig {
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
            namedOpenAICompatible: [:],
            presets: [:]
        )
    }
}
