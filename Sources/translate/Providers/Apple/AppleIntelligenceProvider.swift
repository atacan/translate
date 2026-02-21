import Foundation
import AnyLanguageModel

struct AppleIntelligenceProvider: TranslationProvider {
    let id: ProviderID = .appleIntelligence

    static func validateAvailability() throws {
        #if os(macOS)
        guard #available(macOS 26.0, *) else {
            throw AppError.runtime(
                "Error: Provider 'apple-intelligence' requires macOS 26.0 or later. Current version: \(currentVersionString())."
            )
        }
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw AppError.runtime("Error: Provider 'apple-intelligence' is unavailable on this Mac.")
        }
        #else
        throw AppError.runtime("Error: Provider 'apple-intelligence' is only available on macOS.")
        #endif
    }

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        #if os(macOS)
        guard #available(macOS 26.0, *) else {
            throw ProviderError.unsupported(
                "Error: Provider 'apple-intelligence' requires macOS 26.0 or later. Current version: \(Self.currentVersionString())."
            )
        }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw ProviderError.unsupported("Error: Provider 'apple-intelligence' is unavailable on this Mac.")
        }

        let instructions = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session: LanguageModelSession
        if let instructions, !instructions.isEmpty {
            session = LanguageModelSession(model: model, instructions: instructions)
        } else {
            session = LanguageModelSession(model: model)
        }

        let promptText = request.userPrompt ?? request.text
        do {
            let response: LanguageModelSession.Response<String> = try await session.respond(
                to: Prompt(promptText),
                generating: String.self
            )
            if response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProviderError.invalidResponse("Provider returned an empty response.")
            }
            return ProviderResult(text: response.content, usage: nil, statusCode: nil, headers: [:])
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            throw ProviderError.transport("Error: apple-intelligence request failed: \(error.localizedDescription)")
        }
        #else
        throw ProviderError.unsupported("Error: Provider 'apple-intelligence' is only available on macOS.")
        #endif
    }

    private static func currentVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
