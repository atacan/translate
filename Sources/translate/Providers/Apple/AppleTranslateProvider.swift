import Foundation

struct AppleTranslateProvider: TranslationProvider {
    let id: ProviderID = .appleTranslate

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        throw ProviderError.unsupported("Error: Provider 'apple-translate' is not implemented in this milestone yet.")
    }
}
