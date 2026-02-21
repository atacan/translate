import XCTest
import StringCatalog
@testable import translate

final class CatalogWorkflowTests: XCTestCase {
    func testCatalogWorkflowWritesTranslatedCatalog() async throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let sourceURL = tempDir.appendingPathComponent("Localizable.xcstrings")
        let destinationURL = tempDir.appendingPathComponent("Localizable_FR.xcstrings")

        let sourceCatalog = StringCatalog(
            sourceLanguage: "en",
            strings: [
                "greeting": StringEntry(
                    comment: "Greeting",
                    localizations: [
                        "en": StringLocalization(
                            stringUnit: StringUnit(state: .needsReview, value: "Hello")
                        )
                    ]
                )
            ],
            version: "1.0"
        )
        try sourceCatalog.encodePrettyToString().write(to: sourceURL, atomically: true, encoding: .utf8)

        let provider = MockTranslationProvider { request in
            ProviderResult(
                text: "TR:\(request.text)",
                usage: nil,
                statusCode: 200,
                headers: [:]
            )
        }

        let workflow = CatalogWorkflow()
        let file = ResolvedInputFile(path: sourceURL, matchedByGlob: false)
        let result = await workflow.translateCatalogFile(
            file: file,
            targetLanguage: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false),
            provider: provider,
            jobs: 2,
            outputMode: .perFile([OutputTarget(source: file, destination: destinationURL, inPlace: false)], inPlace: false),
            destinationMap: [file: destinationURL],
            writer: OutputWriter(
                terminal: TerminalIO(quiet: true, verbose: false),
                prompter: ConfirmationPrompter(terminal: TerminalIO(quiet: true, verbose: false), assumeYes: true)
            ),
            terminal: TerminalIO(quiet: true, verbose: false),
            network: NetworkRuntimeConfig(timeoutSeconds: 120, retries: 0, retryBaseDelaySeconds: 1)
        )

        XCTAssertTrue(result.success, result.errorMessage ?? "unexpected error")

        let translatedCatalog = try StringCatalog(contentsOf: destinationURL)
        let translatedValue = translatedCatalog.strings["greeting"]?
            .localizations?["fr"]?
            .stringUnit?
            .value
        XCTAssertEqual(translatedValue, "TR:Hello")
    }

    func testCatalogWorkflowReportsSegmentFailuresButStillWritesOutput() async throws {
        let tempDir = try TestSupport.makeTemporaryDirectory()
        let sourceURL = tempDir.appendingPathComponent("Localizable.xcstrings")
        let destinationURL = tempDir.appendingPathComponent("Localizable_FR.xcstrings")

        let sourceCatalog = StringCatalog(
            sourceLanguage: "en",
            strings: [
                "ok": StringEntry(localizations: ["en": StringLocalization(stringUnit: StringUnit(state: .needsReview, value: "Hello"))]),
                "bad": StringEntry(localizations: ["en": StringLocalization(stringUnit: StringUnit(state: .needsReview, value: "Boom"))]),
            ],
            version: "1.0"
        )
        try sourceCatalog.encodePrettyToString().write(to: sourceURL, atomically: true, encoding: .utf8)

        let provider = MockTranslationProvider { request in
            if request.text == "Boom" {
                throw ProviderError.transport("failure")
            }
            return ProviderResult(text: "OK:\(request.text)", usage: nil, statusCode: 200, headers: [:])
        }

        let workflow = CatalogWorkflow()
        let file = ResolvedInputFile(path: sourceURL, matchedByGlob: false)
        let result = await workflow.translateCatalogFile(
            file: file,
            targetLanguage: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false),
            provider: provider,
            jobs: 2,
            outputMode: .perFile([OutputTarget(source: file, destination: destinationURL, inPlace: false)], inPlace: false),
            destinationMap: [file: destinationURL],
            writer: OutputWriter(
                terminal: TerminalIO(quiet: true, verbose: false),
                prompter: ConfirmationPrompter(terminal: TerminalIO(quiet: true, verbose: false), assumeYes: true)
            ),
            terminal: TerminalIO(quiet: true, verbose: false),
            network: NetworkRuntimeConfig(timeoutSeconds: 120, retries: 0, retryBaseDelaySeconds: 1)
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.errorMessage?.contains("segment(s) failed in catalog translation") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }
}
