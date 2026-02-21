import Foundation

struct AnthropicProvider: TranslationProvider {
    let id: ProviderID = .anthropic
    let baseURL: String
    let model: String
    let apiKey: String
    let httpClient: HTTPClient

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        guard let endpoint = messagesURL(from: baseURL) else {
            throw ProviderError.transport("Invalid base URL '\(baseURL)' for anthropic provider.")
        }

        let promptText = request.userPrompt ?? request.text
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "text",
                    "text": promptText,
                ]],
            ]],
        ]
        if let system = request.systemPrompt, !system.isEmpty {
            payload["system"] = system
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        ]

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

        let outputText = extractContent(from: json)
        if outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProviderError.invalidResponse("Provider returned an empty response.")
        }

        let usage = json["usage"] as? [String: Any]
        return ProviderResult(
            text: outputText,
            usage: UsageInfo(
                inputTokens: usage?["input_tokens"] as? Int,
                outputTokens: usage?["output_tokens"] as? Int
            ),
            statusCode: response.statusCode,
            headers: response.headers
        )
    }

    private func messagesURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.hasSuffix("v1") {
            components.path = "/\(basePath)/messages"
        } else if basePath.isEmpty {
            components.path = "/v1/messages"
        } else {
            components.path = "/\(basePath)/v1/messages"
        }
        return components.url
    }

    private func extractContent(from json: [String: Any]) -> String {
        guard let content = json["content"] as? [[String: Any]] else {
            return ""
        }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    private func isContextWindowError(_ body: String) -> Bool {
        let lowered = body.lowercased()
        return lowered.contains("context") && (lowered.contains("length") || lowered.contains("token") || lowered.contains("window"))
    }
}
