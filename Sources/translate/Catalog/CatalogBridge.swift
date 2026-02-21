import Foundation
import CatalogTranslation
import CatalogTranslationLLM
import StringCatalog

enum CatalogBridge {
    static func makeTranslator(
        provider: any TranslationProvider,
        timeoutSeconds: Int,
        network: NetworkRuntimeConfig
    ) -> any CatalogTextTranslator {
        LLMTranslator { request, systemPrompt, userPrompt in
            let providerRequest = ProviderRequest(
                from: normalizeLanguage(code: request.sourceLanguage.rawValue),
                to: normalizeLanguage(code: request.targetLanguage.rawValue),
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                text: request.text,
                timeoutSeconds: timeoutSeconds,
                network: network
            )

            let result = try await provider.translate(providerRequest)
            return ResponseSanitizer.stripWrappingCodeFence(result.text).text
        }
    }

    private static func normalizeLanguage(code: String) -> NormalizedLanguage {
        NormalizedLanguage(
            input: code,
            displayName: LanguageCode(rawValue: code).englishDisplayName,
            providerCode: code,
            isAuto: false
        )
    }
}
