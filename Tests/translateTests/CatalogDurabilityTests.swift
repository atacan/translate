import XCTest
import StringCatalog
import CatalogTranslation
@testable import translate

final class CatalogDurabilityTests: XCTestCase {
    private let french = NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false)
    private let quiet = TerminalIO(quiet: true, verbose: false)

    func testProgressIsSavedToDestinationDuringTheRun() async throws {
        let (file, destination) = try makeCatalogFile(count: 30)
        let calls = CallCounter()
        let snapshotAtCall28 = TextBox()

        let provider = MockTranslationProvider { request in
            // By the 28th request the 25-segment checkpoint has been written.
            if await calls.next() == 28 {
                await snapshotAtCall28.set(try? String(contentsOf: destination, encoding: .utf8))
            }
            return ProviderResult(text: "FR:\(request.text)", usage: nil, statusCode: 200, headers: [:])
        }

        let result = await translate(file, to: destination, provider: provider, inPlace: false)

        XCTAssertTrue(result.success, result.errorMessage ?? "")
        let snapshot = await snapshotAtCall28.value
        let partial = try XCTUnwrap(snapshot, "No checkpoint was written during the run")
        let partialCatalog = try JSONDecoder().decode(StringCatalog.self, from: Data(partial.utf8))
        let translatedSoFar = partialCatalog.strings.values.filter { $0.localizations?["fr"]?.stringUnit?.value.hasPrefix("FR:") == true }
        XCTAssertGreaterThanOrEqual(translatedSoFar.count, 25)
        XCTAssertLessThan(translatedSoFar.count, 30)
        XCTAssertEqual(try translatedCount(destination), 30)
    }

    func testAuthenticationErrorStopsEarlyAndKeepsCompletedSegments() async throws {
        let (file, destination) = try makeCatalogFile(count: 40)
        let calls = CallCounter()
        let provider = MockTranslationProvider { request in
            if await calls.next() > 5 {
                throw ProviderError.http(statusCode: 401, headers: [:], body: "invalid api key")
            }
            return ProviderResult(text: "FR:\(request.text)", usage: nil, statusCode: 200, headers: [:])
        }

        let result = await translate(file, to: destination, provider: provider, inPlace: false)

        let callCount = await calls.value
        XCTAssertEqual(callCount, 6)
        XCTAssertFalse(result.success)
        let message = try XCTUnwrap(result.errorMessage)
        XCTAssertTrue(message.contains("Stopped early"), message)
        XCTAssertTrue(message.contains("invalid api key"), message)
        XCTAssertTrue(message.contains("5 of 40 segment(s) translated; 34 not attempted"), message)
        XCTAssertTrue(message.contains("translate --in-place --to fr"), message)
        XCTAssertEqual(try translatedCount(destination), 5)
    }

    func testRepeatedTransientFailuresStopTheRun() async throws {
        let (file, destination) = try makeCatalogFile(count: 40)
        let calls = CallCounter()
        let provider = MockTranslationProvider { _ in
            _ = await calls.next()
            throw ProviderError.timeout(seconds: 1)
        }

        let result = await translate(file, to: destination, provider: provider, inPlace: false)

        let callCount = await calls.value
        XCTAssertEqual(callCount, CatalogBridge.maxConsecutiveFailures(jobs: 1))
        XCTAssertTrue(result.errorMessage?.contains("failed in a row") == true, result.errorMessage ?? "")
    }

    func testInPlaceRerunResumesWithOnlyRemainingSegments() async throws {
        let (file, _) = try makeCatalogFile(count: 20)
        let failingCalls = CallCounter()
        let failing = MockTranslationProvider { request in
            if await failingCalls.next() > 8 { throw ProviderError.http(statusCode: 456, headers: [:], body: "quota exceeded") }
            return ProviderResult(text: "FR:\(request.text)", usage: nil, statusCode: 200, headers: [:])
        }
        let first = await translate(file, to: file.path, provider: failing, inPlace: true)
        XCTAssertFalse(first.success)
        XCTAssertTrue(first.errorMessage?.contains("rerun the same command") == true, first.errorMessage ?? "")
        XCTAssertEqual(try translatedCount(file.path), 8)

        let resumedCalls = CallCounter()
        let working = MockTranslationProvider { request in
            _ = await resumedCalls.next()
            return ProviderResult(text: "FR:\(request.text)", usage: nil, statusCode: 200, headers: [:])
        }
        let second = await translate(file, to: file.path, provider: working, inPlace: true)

        XCTAssertTrue(second.success, second.errorMessage ?? "")
        let resumedCount = await resumedCalls.value
        XCTAssertEqual(resumedCount, 12)
        XCTAssertEqual(try translatedCount(file.path), 20)
    }

    func testAnyLanguageModelHTTPErrorKeepsItsStatus() {
        struct FakeURLSessionError: Error, CustomStringConvertible {
            var description: String { "HTTP error (Status 401): Incorrect API key provided" }
        }
        let mapped = AnyLanguageModelTextProvider.mapError(FakeURLSessionError(), providerName: "openai", timeoutSeconds: 10)
        XCTAssertEqual(mapped.statusCode, 401)
        XCTAssertEqual(mapped.message, "API error (HTTP 401): Incorrect API key provided")
        XCTAssertTrue(CatalogBridge.segmentError(for: mapped) is CatalogTranslationAbort)
    }

    // MARK: - Helpers

    private func translate(_ file: ResolvedInputFile, to destination: URL, provider: MockTranslationProvider, inPlace: Bool) async -> TranslationFileResult {
        await CatalogWorkflow().translateCatalogFile(
            file: file,
            targetLanguage: french,
            provider: provider,
            jobs: 1,
            outputMode: .perFile([OutputTarget(source: file, destination: destination, inPlace: inPlace)], inPlace: inPlace),
            destinationMap: [file: destination],
            writer: OutputWriter(
                terminal: quiet,
                prompter: ConfirmationPrompter(terminal: quiet, assumeYes: true),
                skipOverwriteConfirmation: inPlace
            ),
            terminal: quiet,
            network: NetworkRuntimeConfig(timeoutSeconds: 10, retries: 0, retryBaseDelaySeconds: 1)
        )
    }

    private func makeCatalogFile(count: Int) throws -> (ResolvedInputFile, URL) {
        let dir = try TestSupport.makeTemporaryDirectory()
        let source = dir.appendingPathComponent("Localizable.xcstrings")
        var strings: [String: StringEntry] = [:]
        for index in 0..<count {
            strings[String(format: "key%03d", index)] = StringEntry(
                localizations: ["en": StringLocalization(stringUnit: StringUnit(state: .translated, value: "Text \(index)"))]
            )
        }
        try StringCatalog(sourceLanguage: "en", strings: strings, version: "1.0")
            .encodePrettyToString().write(to: source, atomically: true, encoding: .utf8)
        return (ResolvedInputFile(path: source, matchedByGlob: false), dir.appendingPathComponent("Localizable_FR.xcstrings"))
    }

    private func translatedCount(_ url: URL) throws -> Int {
        let catalog = try StringCatalog(contentsOf: url)
        return catalog.strings.values.filter { $0.localizations?["fr"]?.stringUnit?.value.hasPrefix("FR:") == true }.count
    }
}

private actor CallCounter {
    private(set) var value = 0
    func next() -> Int { value += 1; return value }
}

private actor TextBox {
    private(set) var value: String?
    func set(_ text: String?) { value = text }
}
