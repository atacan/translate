import Foundation
import CatalogTranslation
import StringCatalog

/// The dependency owns segment selection. Record its actual jobs without calling a provider
/// so dry-run and execution can share catalog parsing and pending-work selection.
struct CatalogPendingPlan: Sendable {
    let catalog: StringCatalog
    let targetLanguage: LanguageCode
    let requests: [TranslationRequest]

    static func prepare(file: ResolvedInputFile, targetLanguage: NormalizedLanguage, jobs: Int) async throws -> Self {
        let catalog: StringCatalog
        do { catalog = try StringCatalog(contentsOf: file.path) }
        catch let error as DecodingError {
            throw AppError.runtime("Invalid catalog '\(file.path.path)': \(String(describing: error)). Check the .xcstrings JSON structure and required sourceLanguage, strings, and version fields.")
        }
        let target = LanguageCode(rawValue: targetLanguage.providerCode)
        let recorder = CatalogRequestRecorder()
        _ = try await CatalogTranslationEngine(
            translator: recorder, options: TranslationOptions(maxConcurrentRequests: jobs)
        ).translateCatalog(catalog, to: target, mode: .bestEffort)
        let requests = await recorder.requests.sorted {
            let left = ($0.stringKey, CatalogBridge.segmentLabel($0.segment))
            let right = ($1.stringKey, CatalogBridge.segmentLabel($1.segment))
            return left < right
        }
        return Self(catalog: catalog, targetLanguage: target, requests: requests)
    }

    func translate(using translator: any CatalogTextTranslator, jobs: Int) async throws -> CatalogTranslationResult {
        try await CatalogTranslationEngine(
            translator: translator, options: TranslationOptions(maxConcurrentRequests: jobs)
        ).translateCatalog(catalog, to: targetLanguage, mode: .bestEffort)
    }

    func sourceWarnings(configuredSource: NormalizedLanguage, filename: String) -> [String] {
        guard !configuredSource.isAuto,
              configuredSource.providerCode.caseInsensitiveCompare(catalog.sourceLanguage.rawValue) != .orderedSame else { return [] }
        return ["\(filename): catalog sourceLanguage '\(catalog.sourceLanguage.englishDisplayName) (\(catalog.sourceLanguage.rawValue))' overrides configured source '\(configuredSource.displayName) (\(configuredSource.providerCode))'. --from and preset/config source settings do not change catalog source selection."]
    }
}

private actor CatalogRequestRecorder: CatalogTextTranslator {
    private(set) var requests: [TranslationRequest] = []

    func translate(_ request: TranslationRequest) async throws -> String {
        requests.append(request)
        return request.text
    }
}
