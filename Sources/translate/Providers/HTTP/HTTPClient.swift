import Foundation

struct HTTPRequest {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?
    let timeoutSeconds: Int
    let network: NetworkRuntimeConfig
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

struct HTTPClient: Sendable {
    typealias Sender = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Sleeper = @Sendable (Double) async throws -> Void
    private let sender: Sender
    private let sleeper: Sleeper

    init(
        sender: @escaping Sender = { request in
            try await URLSession.shared.data(for: request)
        },
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.sender = sender
        self.sleeper = sleeper
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let maxAttempts = max(1, request.network.retries + 1)
        for attempt in 1...maxAttempts {
            let response = try await singleAttempt(request)
            if attempt < maxAttempts && shouldRetry(statusCode: response.statusCode) {
                let delaySeconds = retryDelay(
                    attempt: attempt,
                    baseDelaySeconds: request.network.retryBaseDelaySeconds,
                    headers: response.headers
                )
                try await sleeper(delaySeconds)
                continue
            }
            return response
        }

        throw ProviderError.transport("Unknown HTTP error.")
    }

    private func singleAttempt(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = TimeInterval(request.timeoutSeconds)
        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (data, response) = try await sender(urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderError.invalidResponse("Invalid HTTP response.")
            }

            let headers = normalizeHeaders(httpResponse.allHeaderFields)
            return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw ProviderError.timeout(seconds: request.timeoutSeconds)
            }
            if let providerError = error as? ProviderError {
                throw providerError
            }
            throw ProviderError.transport(error.localizedDescription)
        }
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [429, 500, 502, 503, 504].contains(statusCode)
    }

    private func retryDelay(attempt: Int, baseDelaySeconds: Int, headers: [String: String]?) -> Double {
        if let headers,
           let retryAfterHeader = headerValue("retry-after", in: headers),
           let retryAfter = parseRetryAfter(retryAfterHeader)
        {
            return retryAfter
        }

        let base = max(1, baseDelaySeconds)
        let exponential = min(Double(base) * pow(2.0, Double(attempt - 1)), 30.0)
        let jitter = exponential * 0.2
        return max(0, exponential + Double.random(in: -jitter...jitter))
    }

    private func parseRetryAfter(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(trimmed), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: trimmed) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    private func normalizeHeaders(_ rawHeaders: [AnyHashable: Any]) -> [String: String] {
        var headers: [String: String] = [:]
        for (rawKey, rawValue) in rawHeaders {
            let key = String(describing: rawKey)
            let value = String(describing: rawValue)
            headers[key] = value
        }
        return headers
    }
}
