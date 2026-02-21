import Foundation
import DeepLAPI
import DeepLAPITypes
import OpenAPIAsyncHTTPClient
import HTTPTypes

struct DeepLProvider: TranslationProvider {
    let id: ProviderID = .deepl
    let apiKey: String

    typealias TranslateExecutor = @Sendable (Operations.translateText.Input.Body) async throws -> Operations.translateText.Output
    typealias Sleeper = @Sendable (Double) async throws -> Void

    private let executeTranslate: TranslateExecutor
    private let sleeper: Sleeper

    init(
        apiKey: String,
        executeTranslate: TranslateExecutor? = nil,
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.apiKey = apiKey
        self.executeTranslate = executeTranslate ?? Self.liveExecutor(apiKey: apiKey)
        self.sleeper = sleeper
    }

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        let sourceLanguage = try resolveSourceLanguage(request.from)
        let targetLanguage = try resolveTargetLanguage(request.to)

        let body: Operations.translateText.Input.Body = .json(
            .init(
                text: [request.text],
                source_lang: sourceLanguage,
                target_lang: targetLanguage
            )
        )

        let retryPolicy = RetryPolicy(network: request.network, sleeper: sleeper)
        for attempt in 1...retryPolicy.maxAttempts {
            let output: Operations.translateText.Output
            do {
                output = try await withTimeout(seconds: request.timeoutSeconds) {
                    try await executeTranslate(body)
                }
            } catch {
                let mappedError = mapExecutorError(error, timeoutSeconds: request.timeoutSeconds)
                if shouldRetry(error: mappedError, attempt: attempt, retryPolicy: retryPolicy) {
                    try await retryPolicy.sleepBeforeRetry(attempt: attempt, headers: [:])
                    continue
                }
                throw mappedError
            }

            switch output {
            case .ok(let ok):
                let payload = try ok.body.json
                guard let text = payload.translations?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else {
                    throw ProviderError.invalidResponse("Provider returned an empty response.")
                }
                let headers = traceHeaderDictionary(ok.headers.X_hyphen_Trace_hyphen_ID)
                return ProviderResult(text: text, usage: nil, statusCode: 200, headers: headers)

            case .badRequest(let response):
                throw ProviderError.http(statusCode: 400, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .forbidden(let response):
                throw ProviderError.http(statusCode: 403, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .notFound(let response):
                throw ProviderError.http(statusCode: 404, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .contentTooLarge(let response):
                throw ProviderError.http(statusCode: 413, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .uriTooLong(let response):
                throw ProviderError.http(statusCode: 414, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .tooManyRequests(let response):
                if retryPolicy.shouldRetry(statusCode: 429, attempt: attempt) {
                    let headers = traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID)
                    try await retryPolicy.sleepBeforeRetry(attempt: attempt, headers: headers)
                    continue
                }
                throw ProviderError.http(statusCode: 429, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .code456(let response):
                throw ProviderError.http(statusCode: 456, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .internalServerError(let response):
                if retryPolicy.shouldRetry(statusCode: 500, attempt: attempt) {
                    let headers = traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID)
                    try await retryPolicy.sleepBeforeRetry(attempt: attempt, headers: headers)
                    continue
                }
                throw ProviderError.http(statusCode: 500, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .gatewayTimeout(let response):
                if retryPolicy.shouldRetry(statusCode: 504, attempt: attempt) {
                    let headers = traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID)
                    try await retryPolicy.sleepBeforeRetry(attempt: attempt, headers: headers)
                    continue
                }
                throw ProviderError.http(statusCode: 504, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .code529(let response):
                throw ProviderError.http(statusCode: 529, headers: traceHeaderDictionary(response.headers.X_hyphen_Trace_hyphen_ID), body: "")
            case .undocumented(let statusCode, let payload):
                let headers = dictionary(from: payload.headerFields)
                if retryPolicy.shouldRetry(statusCode: statusCode, attempt: attempt) {
                    try await retryPolicy.sleepBeforeRetry(attempt: attempt, headers: headers)
                    continue
                }
                throw ProviderError.http(statusCode: statusCode, headers: headers, body: "")
            }
        }

        throw ProviderError.transport("Unknown DeepL API error.")
    }

    private static func liveExecutor(apiKey: String) -> TranslateExecutor {
        { body in
            let serverURL = try apiKey.hasSuffix(":fx") ? Servers.Server2.url() : Servers.Server1.url()
            let client = Client(
                serverURL: serverURL,
                transport: AsyncHTTPClientTransport(),
                middlewares: [AuthenticationMiddleware(apiKey: "DeepL-Auth-Key \(apiKey)")]
            )
            return try await client.translateText(body: body)
        }
    }

    private func resolveSourceLanguage(_ language: NormalizedLanguage) throws -> Components.Schemas.SourceLanguage? {
        guard !language.isAuto else { return nil }
        let mappedCode = mapSourceLanguageCode(language.providerCode)
        guard let source = Components.Schemas.SourceLanguage(rawValue: mappedCode) else {
            throw ProviderError.unsupported("Error: Source language '\(language.input)' is not supported by provider 'deepl'.")
        }
        return source
    }

    private func resolveTargetLanguage(_ language: NormalizedLanguage) throws -> Components.Schemas.TargetLanguage {
        let mappedCode = mapTargetLanguageCode(language.providerCode)
        guard let target = Components.Schemas.TargetLanguage(rawValue: mappedCode) else {
            throw ProviderError.unsupported("Error: Target language '\(language.input)' is not supported by provider 'deepl'.")
        }
        return target
    }

    private func mapSourceLanguageCode(_ code: String) -> String {
        let normalized = canonicalLanguageCode(code)
        switch normalized {
        case "ZH-CN", "ZH-TW", "ZH-HANS", "ZH-HANT":
            return "ZH"
        case "EN-GB", "EN-US":
            return "EN"
        default:
            return normalized
        }
    }

    private func mapTargetLanguageCode(_ code: String) -> String {
        let normalized = canonicalLanguageCode(code)
        switch normalized {
        case "ZH-CN":
            return "ZH-HANS"
        case "ZH-TW":
            return "ZH-HANT"
        default:
            return normalized
        }
    }

    private func canonicalLanguageCode(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").uppercased()
    }

    private func shouldRetry(error: ProviderError, attempt: Int, retryPolicy: RetryPolicy) -> Bool {
        guard case .http(let statusCode, _, _) = error else {
            return false
        }
        return retryPolicy.shouldRetry(statusCode: statusCode, attempt: attempt)
    }

    private func traceHeaderDictionary(_ traceID: Components.Headers.X_hyphen_Trace_hyphen_ID?) -> [String: String] {
        guard let traceID else { return [:] }
        return ["X-Trace-ID": traceID]
    }

    private func dictionary(from headers: HTTPFields) -> [String: String] {
        var out: [String: String] = [:]
        for field in headers {
            out[field.name.canonicalName] = field.value
        }
        return out
    }

    private func mapExecutorError(_ error: Error, timeoutSeconds: Int) -> ProviderError {
        if let providerError = error as? ProviderError {
            return providerError
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return ProviderError.timeout(seconds: max(1, timeoutSeconds))
        }
        return ProviderError.transport(error.localizedDescription)
    }

    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let timeoutSeconds = max(1, seconds)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(Double(timeoutSeconds)))
                throw ProviderError.timeout(seconds: timeoutSeconds)
            }

            guard let result = try await group.next() else {
                throw ProviderError.transport("Unknown DeepL API error.")
            }
            group.cancelAll()
            return result
        }
    }
}
