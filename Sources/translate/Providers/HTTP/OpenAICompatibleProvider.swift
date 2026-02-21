import Foundation

struct OpenAIStreamParser {
    static func payload(fromSSELine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else {
            return nil
        }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty, payload != "[DONE]" else {
            return nil
        }
        return payload
    }

    static func deltaContent(from json: [String: Any]) -> String {
        guard
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let delta = first["delta"] as? [String: Any]
        else {
            return ""
        }

        if let content = delta["content"] as? String {
            return content
        }

        if let contentParts = delta["content"] as? [[String: Any]] {
            return contentParts.compactMap { $0["text"] as? String }.joined()
        }

        return ""
    }
}

struct OpenAICompatibleProvider: TranslationProvider {
    let id: ProviderID
    let baseURL: String
    let model: String
    let apiKey: String?
    let httpClient: HTTPClient

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        guard let endpoint = chatCompletionsURL(from: baseURL) else {
            throw ProviderError.transport("Invalid --base-url '\(baseURL)'.")
        }

        let messages = messages(for: request)

        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": messages,
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let headers = requestHeaders()

        let response = try await httpClient.send(
            HTTPRequest(
                url: endpoint,
                method: "POST",
                headers: headers,
                body: body,
                timeoutSeconds: request.timeoutSeconds,
                network: request.network
            )
        )

        guard (200...299).contains(response.statusCode) else {
            let bodyText = String(data: response.body, encoding: .utf8) ?? ""
            if response.statusCode == 400, isContextWindowError(bodyText) {
                throw ProviderError.invalidResponse("Error: Input exceeds the model's context window. Consider a model with a larger context window, or split the input into smaller files.")
            }
            throw ProviderError.http(statusCode: response.statusCode, headers: response.headers, body: bodyText)
        }

        guard let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw ProviderError.invalidResponse("Provider returned invalid JSON response.")
        }

        let content = extractOpenAIMessageContent(from: json)
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProviderError.invalidResponse("Provider returned an empty response.")
        }

        let usageDict = json["usage"] as? [String: Any]
        let usage = UsageInfo(
            inputTokens: usageDict?["prompt_tokens"] as? Int,
            outputTokens: usageDict?["completion_tokens"] as? Int
        )

        return ProviderResult(text: content, usage: usage, statusCode: response.statusCode, headers: response.headers)
    }

    func streamTranslate(_ request: ProviderRequest) -> AsyncThrowingStream<String, Error>? {
        guard let endpoint = chatCompletionsURL(from: baseURL) else {
            return nil
        }

        let messages = messages(for: request)

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages,
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ProviderError.invalidResponse("Provider request payload could not be encoded."))
            }
        }

        let headers = requestHeaders()
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = body
                    urlRequest.timeoutInterval = TimeInterval(request.timeoutSeconds)
                    for (header, value) in headers {
                        urlRequest.setValue(value, forHTTPHeaderField: header)
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ProviderError.invalidResponse("Invalid HTTP response.")
                    }

                    let normalizedHeaders = normalizeHeaders(httpResponse.allHeaderFields)
                    guard (200...299).contains(httpResponse.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines {
                            bodyText += line
                        }
                        if httpResponse.statusCode == 400, isContextWindowError(bodyText) {
                            throw ProviderError.invalidResponse("Error: Input exceeds the model's context window. Consider a model with a larger context window, or split the input into smaller files.")
                        }
                        throw ProviderError.http(statusCode: httpResponse.statusCode, headers: normalizedHeaders, body: bodyText)
                    }

                    for try await line in bytes.lines {
                        guard let payload = OpenAIStreamParser.payload(fromSSELine: line),
                              let data = payload.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else {
                            continue
                        }

                        let delta = OpenAIStreamParser.deltaContent(from: json)
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }

                    continuation.finish()
                } catch {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        continuation.finish(throwing: ProviderError.timeout(seconds: request.timeoutSeconds))
                        return
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func chatCompletionsURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.hasSuffix("v1") {
            components.path = "/\(basePath)/chat/completions"
        } else if basePath.isEmpty {
            components.path = "/v1/chat/completions"
        } else {
            components.path = "/\(basePath)/v1/chat/completions"
        }

        return components.url
    }

    private func extractOpenAIMessageContent(from json: [String: Any]) -> String {
        guard
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            return ""
        }

        if let content = message["content"] as? String {
            return content
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            return contentParts.compactMap { $0["text"] as? String }.joined()
        }

        return ""
    }

    private func isContextWindowError(_ body: String) -> Bool {
        let lowered = body.lowercased()
        return lowered.contains("context") && (lowered.contains("length") || lowered.contains("token") || lowered.contains("window"))
    }

    private func messages(for request: ProviderRequest) -> [[String: String]] {
        var messages: [[String: String]] = []
        if let system = request.systemPrompt, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": request.userPrompt ?? request.text])
        return messages
    }

    private func requestHeaders() -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return headers
    }

    private func normalizeHeaders(_ rawHeaders: [AnyHashable: Any]) -> [String: String] {
        var headers: [String: String] = [:]
        for (rawKey, rawValue) in rawHeaders {
            headers[String(describing: rawKey)] = String(describing: rawValue)
        }
        return headers
    }
}
