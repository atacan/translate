import XCTest
import Foundation
@testable import translate

final class RetryPolicyTests: XCTestCase {
    func testRetriesOn429AndSucceeds() async throws {
        let attempts = LockedCounter()
        let client = HTTPClient(
            sender: { request in
                let current = await attempts.incrementAndGet()
                let code = current == 1 ? 429 : 200
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: code,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("{}".utf8), response)
            },
            sleeper: { _ in }
        )

        let response = try await client.send(
            HTTPRequest(
                url: URL(string: "https://example.com")!,
                method: "POST",
                headers: [:],
                body: nil,
                timeoutSeconds: 5,
                network: NetworkRuntimeConfig(timeoutSeconds: 5, retries: 2, retryBaseDelaySeconds: 1)
            )
        )

        XCTAssertEqual(response.statusCode, 200)
        let attemptCount = await attempts.currentValue()
        XCTAssertEqual(attemptCount, 2)
    }

    func testDoesNotRetryOn400() async throws {
        let attempts = LockedCounter()
        let client = HTTPClient(
            sender: { request in
                _ = await attempts.incrementAndGet()
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("{}".utf8), response)
            },
            sleeper: { _ in XCTFail("Unexpected retry sleep for non-retryable status.") }
        )

        let response = try await client.send(
            HTTPRequest(
                url: URL(string: "https://example.com")!,
                method: "GET",
                headers: [:],
                body: nil,
                timeoutSeconds: 5,
                network: NetworkRuntimeConfig(timeoutSeconds: 5, retries: 3, retryBaseDelaySeconds: 1)
            )
        )

        XCTAssertEqual(response.statusCode, 400)
        let attemptCount = await attempts.currentValue()
        XCTAssertEqual(attemptCount, 1)
    }

    func testRetryAfterHeaderIsRespectedCaseInsensitive() async throws {
        let attempts = LockedCounter()
        let delays = DelayRecorder()
        let client = HTTPClient(
            sender: { request in
                let current = await attempts.incrementAndGet()
                if current == 1 {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 429,
                        httpVersion: nil,
                        headerFields: ["ReTrY-AfTeR": "7"]
                    )!
                    return (Data("{}".utf8), response)
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("{}".utf8), response)
            },
            sleeper: { seconds in
                await delays.record(seconds: seconds)
            }
        )

        _ = try await client.send(
            HTTPRequest(
                url: URL(string: "https://example.com")!,
                method: "POST",
                headers: [:],
                body: nil,
                timeoutSeconds: 5,
                network: NetworkRuntimeConfig(timeoutSeconds: 5, retries: 1, retryBaseDelaySeconds: 1)
            )
        )

        let attemptCount = await attempts.currentValue()
        XCTAssertEqual(attemptCount, 2)
        let recorded = await delays.recordedValues()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first ?? -1, 7, accuracy: 0.001)
    }
}

actor LockedCounter {
    private var value: Int = 0

    func incrementAndGet() -> Int {
        value += 1
        return value
    }

    func currentValue() -> Int {
        value
    }
}

actor DelayRecorder {
    private var values: [Double] = []

    func record(seconds: Double) {
        values.append(seconds)
    }

    func recordedValues() -> [Double] {
        values
    }
}
