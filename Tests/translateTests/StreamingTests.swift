import XCTest
@testable import translate

final class StreamingTests: XCTestCase {
    func testOpenAIStreamParserExtractsPayloadFromSSEDataLines() {
        XCTAssertEqual(OpenAIStreamParser.payload(fromSSELine: "data: {\"id\":\"x\"}"), "{\"id\":\"x\"}")
        XCTAssertNil(OpenAIStreamParser.payload(fromSSELine: "data: [DONE]"))
        XCTAssertNil(OpenAIStreamParser.payload(fromSSELine: "event: message"))
    }

    func testOpenAIStreamParserExtractsDeltaContent() {
        let stringPayload: [String: Any] = [
            "choices": [["delta": ["content": "Bon"]]],
        ]
        XCTAssertEqual(OpenAIStreamParser.deltaContent(from: stringPayload), "Bon")

        let arrayPayload: [String: Any] = [
            "choices": [[
                "delta": [
                    "content": [
                        ["text": "jour"],
                        ["text": "!"],
                    ],
                ],
            ]],
        ]
        XCTAssertEqual(OpenAIStreamParser.deltaContent(from: arrayPayload), "jour!")
    }
}
