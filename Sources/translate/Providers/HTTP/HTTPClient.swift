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
        let retryPolicy = RetryPolicy(network: request.network, sleeper: sleeper)
        for attempt in 1...retryPolicy.maxAttempts {
            let response = try await singleAttempt(request)
            if retryPolicy.shouldRetry(statusCode: response.statusCode, attempt: attempt) {
                try await retryPolicy.sleepBeforeRetry(attempt: attempt, headers: response.headers)
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

    func shouldRetry(statusCode: Int) -> Bool {
        RetryPolicy.shouldRetry(statusCode: statusCode)
    }

    func retryDelaySeconds(attempt: Int, baseDelaySeconds: Int, headers: [String: String]?) -> Double {
        let retryPolicy = RetryPolicy(
            maxAttempts: max(2, attempt + 1),
            baseDelaySeconds: baseDelaySeconds,
            sleeper: sleeper
        )
        return retryPolicy.delaySeconds(attempt: attempt, headers: headers ?? [:])
    }

    func sleep(seconds: Double) async throws {
        try await sleeper(seconds)
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
