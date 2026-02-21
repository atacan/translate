import Foundation

struct ProviderRequest: Sendable {
    let from: NormalizedLanguage
    let to: NormalizedLanguage
    let systemPrompt: String?
    let userPrompt: String?
    let text: String
    let timeoutSeconds: Int
    let network: NetworkRuntimeConfig
}

struct UsageInfo: Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
}

struct ProviderResult: Sendable {
    let text: String
    let usage: UsageInfo?
    let statusCode: Int?
    let headers: [String: String]
}

enum ProviderError: Error, Sendable {
    case http(statusCode: Int, headers: [String: String], body: String)
    case timeout(seconds: Int)
    case invalidResponse(String)
    case transport(String)
    case unsupported(String)

    var message: String {
        switch self {
        case .http(let statusCode, _, let body):
            if body.isEmpty {
                return "API error (HTTP \(statusCode))."
            }
            return "API error (HTTP \(statusCode)): \(body)"
        case .timeout(let seconds):
            return "Error: Request timed out after \(seconds)s. Use 'translate config set network.timeout_seconds <value>' to increase the limit."
        case .invalidResponse(let message):
            return message
        case .transport(let message):
            return message
        case .unsupported(let message):
            return message
        }
    }

    var statusCode: Int? {
        switch self {
        case .http(let statusCode, _, _):
            statusCode
        default:
            nil
        }
    }
}

protocol TranslationProvider: Sendable {
    var id: ProviderID { get }
    func translate(_ request: ProviderRequest) async throws -> ProviderResult
    func streamTranslate(_ request: ProviderRequest) -> AsyncThrowingStream<String, Error>?
}

extension TranslationProvider {
    func streamTranslate(_ request: ProviderRequest) -> AsyncThrowingStream<String, Error>? {
        nil
    }
}
