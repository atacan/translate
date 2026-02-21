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
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let maxAttempts = max(1, request.network.retries + 1)
        var lastError: ProviderError?

        for attempt in 1...maxAttempts {
            do {
                return try await singleAttempt(request)
            } catch let providerError as ProviderError {
                lastError = providerError

                if attempt == maxAttempts || !shouldRetry(error: providerError) {
                    throw providerError
                }

                let delaySeconds = retryDelay(
                    attempt: attempt,
                    baseDelaySeconds: request.network.retryBaseDelaySeconds,
                    headers: (providerError.statusCode != nil ? headers(from: providerError) : nil)
                )
                try await Task.sleep(for: .seconds(delaySeconds))
            } catch {
                let transport = ProviderError.transport(error.localizedDescription)
                lastError = transport
                if attempt == maxAttempts {
                    throw transport
                }
                let delaySeconds = retryDelay(
                    attempt: attempt,
                    baseDelaySeconds: request.network.retryBaseDelaySeconds,
                    headers: nil
                )
                try await Task.sleep(for: .seconds(delaySeconds))
            }
        }

        throw lastError ?? .transport("Unknown HTTP error")
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
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
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

    private func shouldRetry(error: ProviderError) -> Bool {
        switch error {
        case .timeout:
            return true
        case .transport:
            return true
        case .http(let statusCode, _, _):
            return [429, 500, 502, 503, 504].contains(statusCode)
        default:
            return false
        }
    }

    private func retryDelay(attempt: Int, baseDelaySeconds: Int, headers: [String: String]?) -> Double {
        if let headers,
           let retryAfterHeader = headers.first(where: { $0.key.lowercased() == "retry-after" })?.value,
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

    private func normalizeHeaders(_ rawHeaders: [AnyHashable: Any]) -> [String: String] {
        var headers: [String: String] = [:]
        for (rawKey, rawValue) in rawHeaders {
            let key = String(describing: rawKey)
            let value = String(describing: rawValue)
            headers[key] = value
        }
        return headers
    }

    private func headers(from error: ProviderError) -> [String: String] {
        switch error {
        case .http(_, let headers, _):
            return headers
        default:
            return [:]
        }
    }
}
