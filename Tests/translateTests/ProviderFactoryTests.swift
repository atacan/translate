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

    func testDeepLIsDeferred() {
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
            XCTAssertEqual(appError.message, "Error: Provider 'deepl' is deferred for this milestone.")
            XCTAssertEqual(appError.exitCode, .runtimeError)
        }
    }

    private func makeConfig() -> ResolvedConfig {
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
            providers: [:],
            namedOpenAICompatible: [:],
            presets: [:]
        )
    }
}
