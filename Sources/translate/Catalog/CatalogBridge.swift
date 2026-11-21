import Foundation
import CatalogTranslation
import StringCatalog

/// Render each catalog segment with the same resolved CLI templates used for text.
struct CatalogPromptConfiguration: Sendable {
    let templates: ResolvedPromptSet
    let context: String
    let filename: String
    let format: ResolvedFormat

    func providerRequest(for request: TranslationRequest, network: NetworkRuntimeConfig) -> ProviderRequest {
        let from = CatalogBridge.normalizeLanguage(code: request.sourceLanguage.rawValue)
        let to = CatalogBridge.normalizeLanguage(code: request.targetLanguage.rawValue)
        var contextParts: [String] = []
        let cliContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        // The model sees the user's --context as plain text; only the comment is labeled.
        if !cliContext.isEmpty { contextParts.append(cliContext) }
        if let comment = request.developerComment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextParts.append("Developer comment: \(comment)")
        }
        let rendered = PromptRenderer().render(templates, with: PromptRenderContext(
            text: request.text,
            from: from,
            to: to,
            context: contextParts.joined(separator: "\n"),
            filename: filename,
            format: format,
            stringKey: request.stringKey,
            comment: request.developerComment ?? "",
            segment: CatalogBridge.segmentLabel(request.segment)
        ))
        return ProviderRequest(
            from: from, to: to,
            systemPrompt: rendered.systemPrompt, userPrompt: rendered.userPrompt,
            text: request.text, timeoutSeconds: network.timeoutSeconds, network: network
        )
    }
}

enum CatalogBridge {
    static func makeTranslator(
        provider: any TranslationProvider,
        prompts: CatalogPromptConfiguration,
        network: NetworkRuntimeConfig
    ) -> any CatalogTextTranslator {
        CLITranslator(provider: provider, prompts: prompts, network: network)
    }

    static func normalizeLanguage(code: String) -> NormalizedLanguage {
        NormalizedLanguage(input: code, displayName: LanguageCode(rawValue: code).englishDisplayName, providerCode: code, isAuto: false)
    }

    static func segmentLabel(_ segment: TranslationSegment) -> String {
        switch segment {
        case .stringUnit: return "stringUnit"
        case .stringSet(let index): return "stringSet[\(index)]"
        case .variation(let path): return "variation[\(path)]"
        }
    }

    private struct CLITranslator: CatalogTextTranslator {
        let provider: any TranslationProvider
        let prompts: CatalogPromptConfiguration
        let network: NetworkRuntimeConfig

        func translate(_ request: TranslationRequest) async throws -> String {
            do {
                let result = try await provider.translate(prompts.providerRequest(for: request, network: network))
                return ResponseSanitizer.stripWrappingCodeFence(result.text).text
            } catch let error as ProviderError {
                throw CatalogBridge.segmentError(for: error)
            }
        }
    }

    /// HTTP statuses that will fail every remaining segment the same way: bad credentials,
    /// no permission or billing, unknown model/endpoint, and DeepL's quota exhaustion.
    static let fatalHTTPStatusCodes: Set<Int> = [401, 402, 403, 404, 456]

    /// Readable failure text, marked fatal when retrying other segments cannot help.
    static func segmentError(for error: ProviderError) -> any Error {
        if let status = error.statusCode, fatalHTTPStatusCodes.contains(status) {
            return CatalogTranslationAbort(reason: error.message)
        }
        if case .unsupported = error { return CatalogTranslationAbort(reason: error.message) }
        return CatalogSegmentError(message: error.message)
    }

    /// Stop after this many failures in a row. Concurrent requests can fail together in a
    /// short outage, so the limit grows with the request concurrency.
    static func maxConsecutiveFailures(jobs: Int) -> Int {
        max(10, 2 * max(1, jobs))
    }

    struct CatalogSegmentError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
