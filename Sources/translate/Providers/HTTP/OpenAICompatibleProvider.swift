import Foundation

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

        var messages: [[String: String]] = []
        if let system = request.systemPrompt, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": request.userPrompt ?? request.text])

        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": messages,
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

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
}
