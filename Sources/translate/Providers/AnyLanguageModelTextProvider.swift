import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel

struct AnyLanguageModelTextProvider: TranslationProvider {
    enum Backend: Sendable {
        case openai
        case openAICompatible
        case anthropic
        case ollama
    }

    let id: ProviderID
    let backend: Backend
    let baseURL: String
    let model: String
    let apiKey: String?

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        do {
            let session = try makeSession(for: request)
            let promptText = request.userPrompt ?? request.text
            let response = try await session.respond(to: promptText)
            let text = response.content
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.invalidResponse("Provider returned an empty response.")
            }
            return ProviderResult(text: text, usage: nil, statusCode: nil, headers: [:])
        } catch {
            throw Self.mapError(error, providerName: id.rawValue, timeoutSeconds: request.timeoutSeconds)
        }
    }

    func streamTranslate(_ request: ProviderRequest) -> AsyncThrowingStream<String, Error>? {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = try makeSession(for: request)
                    let promptText = request.userPrompt ?? request.text
                    let stream = session.streamResponse(to: promptText)

                    var previous = ""
                    var emittedAny = false
                    for try await snapshot in stream {
                        let current = Self.accumulatedText(from: snapshot.rawContent)
                        if let delta = Self.deltaChunk(previous: previous, current: current) {
                            continuation.yield(delta)
                            emittedAny = true
                        }
                        previous = current
                    }

                    if !emittedAny && previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw ProviderError.invalidResponse("Provider returned an empty response.")
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: Self.mapError(error, providerName: id.rawValue, timeoutSeconds: request.timeoutSeconds)
                    )
                }
            }
        }
    }

    private func makeSession(for request: ProviderRequest) throws -> LanguageModelSession {
        let model = try makeModel()
        let instructions = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let instructions, !instructions.isEmpty {
            return LanguageModelSession(model: model, instructions: instructions)
        }
        return LanguageModelSession(model: model)
    }

    private func makeModel() throws -> any LanguageModel {
        let providerName = id.rawValue

        switch backend {
        case .openai, .openAICompatible:
            guard let url = Self.normalizeBaseURL(baseURL, for: backend) else {
                throw ProviderError.transport("Invalid base URL '\(baseURL)' for \(providerName) provider.")
            }
            let token = apiKey ?? ""
            return OpenAILanguageModel(
                baseURL: url,
                apiKey: token,
                model: model,
                apiVariant: .chatCompletions
            )

        case .anthropic:
            guard let url = Self.normalizeBaseURL(baseURL, for: backend) else {
                throw ProviderError.transport("Invalid base URL '\(baseURL)' for \(providerName) provider.")
            }
            let token = apiKey ?? ""
            return AnthropicLanguageModel(
                baseURL: url,
                apiKey: token,
                model: model
            )

        case .ollama:
            guard let url = Self.normalizeBaseURL(baseURL, for: backend) else {
                throw ProviderError.transport("Invalid base URL '\(baseURL)' for \(providerName) provider.")
            }
            return OllamaLanguageModel(
                baseURL: url,
                model: model
            )
        }
    }

    static func accumulatedText(from rawContent: GeneratedContent) -> String {
        switch rawContent.kind {
        case .string(let text):
            return text
        default:
            return rawContent.jsonString
        }
    }

    static func deltaChunk(previous: String, current: String) -> String? {
        guard current != previous else { return nil }
        if current.hasPrefix(previous) {
            let index = current.index(current.startIndex, offsetBy: previous.count)
            let suffix = String(current[index...])
            return suffix.isEmpty ? nil : suffix
        }
        return current.isEmpty ? nil : current
    }

    static func normalizeBaseURL(_ raw: String, for backend: Backend) -> URL? {
        guard var components = URLComponents(string: raw) else {
            return nil
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var segments = trimmedPath.split(separator: "/").map(String.init)

        switch backend {
        case .openai, .openAICompatible:
            if segments.last != "v1" {
                segments.append("v1")
            }
        case .anthropic:
            if segments.last == "v1" {
                segments.removeLast()
            }
        case .ollama:
            if segments.last == "v1" {
                segments.removeLast()
            }
        }

        if segments.isEmpty {
            components.path = "/"
        } else {
            components.path = "/\(segments.joined(separator: "/"))/"
        }

        return components.url
    }

    static func mapError(_ error: Error, providerName: String, timeoutSeconds: Int) -> ProviderError {
        if let providerError = error as? ProviderError {
            return providerError
        }

        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timeout(seconds: timeoutSeconds)
        }

        let message = error.localizedDescription
        if message.lowercased().contains("timed out") {
            return .timeout(seconds: timeoutSeconds)
        }

        return .transport("Error: \(providerName) request failed: \(message)")
    }
}
