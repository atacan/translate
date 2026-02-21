import Foundation

struct AppleIntelligenceProvider: TranslationProvider {
    let id: ProviderID = .appleIntelligence

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        throw ProviderError.unsupported("Error: Provider 'apple-intelligence' is not implemented in this milestone yet.")
    }
}
