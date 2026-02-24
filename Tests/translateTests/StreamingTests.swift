import XCTest
@testable import translate

final class StreamingTests: XCTestCase {
    func testSnapshotDeltaChunkReturnsSuffixForCumulativeSnapshots() {
        XCTAssertEqual(
            AnyLanguageModelTextProvider.deltaChunk(previous: "Bon", current: "Bonjour"),
            "jour"
        )
    }

    func testSnapshotDeltaChunkReturnsNilWhenUnchanged() {
        XCTAssertNil(AnyLanguageModelTextProvider.deltaChunk(previous: "Bonjour", current: "Bonjour"))
    }

    func testSnapshotDeltaChunkReturnsWholeTextWhenStreamResets() {
        XCTAssertEqual(
            AnyLanguageModelTextProvider.deltaChunk(previous: "Bonjour", current: "Salut"),
            "Salut"
        )
    }

    func testNormalizeOpenAIBaseURLAppendsV1() throws {
        let url = try XCTUnwrap(
            AnyLanguageModelTextProvider.normalizeBaseURL("http://localhost:1234", for: .openAICompatible)
        )
        XCTAssertEqual(url.absoluteString, "http://localhost:1234/v1/")
    }

    func testNormalizeAnthropicBaseURLStripsV1() throws {
        let url = try XCTUnwrap(
            AnyLanguageModelTextProvider.normalizeBaseURL("https://api.anthropic.com/v1", for: .anthropic)
        )
        XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/")
    }

    func testMapErrorMapsTimeout() {
        let mapped = AnyLanguageModelTextProvider.mapError(
            URLError(.timedOut),
            providerName: "openai",
            timeoutSeconds: 12
        )

        guard case .timeout(let seconds) = mapped else {
            return XCTFail("Expected timeout mapping.")
        }
        XCTAssertEqual(seconds, 12)
    }
}
