import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(Translation)
import Translation
#endif

struct AppleTranslateProvider: TranslationProvider {
    let id: ProviderID = .appleTranslate

    static func validateAvailability() throws {
        #if os(macOS)
        guard #available(macOS 26.0, *) else {
            throw AppError.runtime(
                "Error: Provider 'apple-translate' requires macOS 26.0 or later. Current version: \(currentVersionString())."
            )
        }
        #else
        throw AppError.runtime("Error: Provider 'apple-translate' is only available on macOS.")
        #endif
    }

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        #if canImport(Translation)
        guard #available(macOS 26.0, *) else {
            throw ProviderError.unsupported(
                "Error: Provider 'apple-translate' requires macOS 26.0 or later. Current version: \(Self.currentVersionString())."
            )
        }

        let sourceLanguage = resolveSourceLanguage(for: request)
        let targetLanguage = Locale.Language(identifier: request.to.providerCode)
        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)

        do {
            let response = try await session.translate(request.text)
            let translated = response.targetText
            if translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProviderError.invalidResponse("Provider returned an empty response.")
            }
            return ProviderResult(text: translated, usage: nil, statusCode: nil, headers: [:])
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            throw ProviderError.transport("Error: apple-translate request failed: \(error.localizedDescription)")
        }
        #else
        throw ProviderError.unsupported("Error: Provider 'apple-translate' is only available on macOS.")
        #endif
    }

    #if canImport(Translation)
    @available(macOS 26.0, *)
    private func resolveSourceLanguage(for request: ProviderRequest) -> Locale.Language {
        if !request.from.isAuto {
            return Locale.Language(identifier: request.from.providerCode)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(request.text)
        if let detected = recognizer.dominantLanguage {
            return Locale.Language(identifier: detected.rawValue)
        }

        let fallback = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.Language(identifier: fallback)
    }
    #endif

    private static func currentVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
