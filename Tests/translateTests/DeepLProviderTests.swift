import XCTest
import DeepLAPITypes
@testable import translate

final class DeepLProviderTests: XCTestCase {
    func testTranslateMapsLanguageCodesAndReturnsText() async throws {
        let recorder = DeepLBodyRecorder()
        let provider = DeepLProvider(
            apiKey: "test-key",
            executeTranslate: { body in
                await recorder.record(body)
                return Self.successfulOutput(text: "Merhaba dunya", traceID: "trace-1")
            },
            sleeper: { _ in XCTFail("Unexpected retry sleep.") }
        )

        let result = try await provider.translate(
            makeRequest(
                from: Self.language(input: "en-US", displayName: "English", code: "en-US"),
                to: Self.language(input: "zh-TW", displayName: "Traditional Chinese", code: "zh-TW")
            )
        )

        XCTAssertEqual(result.text, "Merhaba dunya")
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.headers["X-Trace-ID"], "trace-1")

        let payload = try await recorder.lastJSONPayload()
        XCTAssertEqual(payload.source_lang, .EN)
        XCTAssertEqual(payload.target_lang, .ZH_hyphen_HANT)
        XCTAssertEqual(payload.text, ["Hello world"])
    }

    func testTranslateOmitsSourceLanguageWhenAuto() async throws {
        let recorder = DeepLBodyRecorder()
        let provider = DeepLProvider(
            apiKey: "test-key",
            executeTranslate: { body in
                await recorder.record(body)
                return Self.successfulOutput(text: "Bonjour")
            },
            sleeper: { _ in XCTFail("Unexpected retry sleep.") }
        )

        _ = try await provider.translate(
            makeRequest(
                from: Self.language(input: "auto", displayName: BuiltInDefaults.sourceLanguagePlaceholder, code: "auto", isAuto: true),
                to: Self.language(input: "fr", displayName: "French", code: "fr")
            )
        )

        let payload = try await recorder.lastJSONPayload()
        XCTAssertNil(payload.source_lang)
        XCTAssertEqual(payload.target_lang, .FR)
    }

    func testTranslateRetriesOn429ThenSucceeds() async throws {
        let attempts = DeepLAttemptCounter()
        let delays = DeepLDelayRecorder()
        let provider = DeepLProvider(
            apiKey: "test-key",
            executeTranslate: { _ in
                let count = await attempts.incrementAndGet()
                if count == 1 {
                    return .tooManyRequests(.init())
                }
                return Self.successfulOutput(text: "Hola")
            },
            sleeper: { seconds in
                await delays.record(seconds)
            }
        )

        let result = try await provider.translate(makeRequest(retries: 1))
        XCTAssertEqual(result.text, "Hola")
        let attemptCount = await attempts.currentValue()
        let delayCount = await delays.count()
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(delayCount, 1)
    }

    func testTranslateRejectsUnsupportedTargetLanguage() async {
        let attempts = DeepLAttemptCounter()
        let provider = DeepLProvider(
            apiKey: "test-key",
            executeTranslate: { _ in
                _ = await attempts.incrementAndGet()
                return Self.successfulOutput(text: "ignored")
            }
        )

        do {
            _ = try await provider.translate(
                makeRequest(
                    to: Self.language(input: "xx", displayName: "Unknown", code: "xx")
                )
            )
            XCTFail("Expected unsupported language error.")
        } catch let error as ProviderError {
            guard case .unsupported(let message) = error else {
                return XCTFail("Expected unsupported error, got \(error).")
            }
            XCTAssertEqual(message, "Error: Target language 'xx' is not supported by provider 'deepl'.")
            let attemptCount = await attempts.currentValue()
            XCTAssertEqual(attemptCount, 0)
        } catch {
            XCTFail("Expected ProviderError, got \(error).")
        }
    }

    func testTranslateThrowsInvalidResponseWhenTextIsEmpty() async {
        let provider = DeepLProvider(
            apiKey: "test-key",
            executeTranslate: { _ in
                .ok(.init(body: .json(.init(translations: [.init(text: "   ")]))))
            }
        )

        do {
            _ = try await provider.translate(makeRequest())
            XCTFail("Expected invalid response error.")
        } catch let error as ProviderError {
            guard case .invalidResponse(let message) = error else {
                return XCTFail("Expected invalid response error, got \(error).")
            }
            XCTAssertEqual(message, "Provider returned an empty response.")
        } catch {
            XCTFail("Expected ProviderError, got \(error).")
        }
    }

    private func makeRequest(
        from: NormalizedLanguage? = nil,
        to: NormalizedLanguage? = nil,
        text: String = "Hello world",
        retries: Int = 0
    ) -> ProviderRequest {
        let resolvedFrom = from ?? Self.language(input: "en", displayName: "English", code: "en")
        let resolvedTo = to ?? Self.language(input: "es", displayName: "Spanish", code: "es")
        return ProviderRequest(
            from: resolvedFrom,
            to: resolvedTo,
            systemPrompt: nil,
            userPrompt: nil,
            text: text,
            timeoutSeconds: 2,
            network: NetworkRuntimeConfig(timeoutSeconds: 2, retries: retries, retryBaseDelaySeconds: 1)
        )
    }

    private static func successfulOutput(text: String, traceID: String? = nil) -> Operations.translateText.Output {
        .ok(
            .init(
                headers: .init(X_hyphen_Trace_hyphen_ID: traceID),
                body: .json(.init(translations: [.init(text: text)]))
            )
        )
    }

    private static func language(
        input: String,
        displayName: String,
        code: String,
        isAuto: Bool = false
    ) -> NormalizedLanguage {
        NormalizedLanguage(input: input, displayName: displayName, providerCode: code, isAuto: isAuto)
    }
}

private actor DeepLBodyRecorder {
    private var body: Operations.translateText.Input.Body?

    func record(_ body: Operations.translateText.Input.Body) {
        self.body = body
    }

    func lastJSONPayload() throws -> Operations.translateText.Input.Body.jsonPayload {
        guard let body else {
            throw DeepLRecorderError.missingBody
        }
        switch body {
        case .json(let payload):
            return payload
        case .urlEncodedForm:
            throw DeepLRecorderError.unexpectedBodyFormat
        }
    }
}

private actor DeepLAttemptCounter {
    private var value = 0

    func incrementAndGet() -> Int {
        value += 1
        return value
    }

    func currentValue() -> Int {
        value
    }
}

private actor DeepLDelayRecorder {
    private var recorded: [Double] = []

    func record(_ delay: Double) {
        recorded.append(delay)
    }

    func count() -> Int {
        recorded.count
    }
}

private enum DeepLRecorderError: Error {
    case missingBody
    case unexpectedBodyFormat
}
