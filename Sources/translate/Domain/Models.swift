import Foundation
import ArgumentParser
import TOMLKit

enum ProviderID: String, CaseIterable, Sendable {
    case openai
    case anthropic
    case gemini
    case openResponses = "open-responses"
    case ollama
    case openAICompatible = "openai-compatible"
    case coreml
    case mlx
    case llama
    case appleIntelligence = "apple-intelligence"
    case appleTranslate = "apple-translate"
    case deepl

    static let builtInNames: Set<String> = Set(Self.allCases.map(\.rawValue))
}

enum FormatHint: String, CaseIterable, Sendable, ExpressibleByArgument {
    case auto
    case text
    case markdown
    case html
}

enum ResolvedFormat: String, Sendable {
    case text
    case markdown
    case html

    var promptValue: String {
        switch self {
        case .text:
            return "text"
        case .markdown:
            return "markdown"
        case .html:
            return "HTML"
        }
    }
}

struct NormalizedLanguage: Sendable {
    let input: String
    let displayName: String
    let providerCode: String
    let isAuto: Bool

    var outputSuffixCode: String {
        providerCode.split(separator: "-").first.map(String.init)?.uppercased() ?? providerCode.uppercased()
    }
}

struct ProviderConfigEntry: Sendable {
    var baseURL: String?
    var model: String?
    var apiKey: String?
}

struct PresetDefinition: Sendable {
    var name: String
    var source: PresetSource
    var description: String?
    var systemPrompt: String?
    var systemPromptFile: String?
    var userPrompt: String?
    var userPromptFile: String?
    var provider: String?
    var model: String?
    var from: String?
    var to: String?
    var format: String?
}

enum PresetSource: String, Sendable {
    case builtIn = "built-in"
    case userDefined = "user-defined"
}

struct NetworkRuntimeConfig: Sendable {
    let timeoutSeconds: Int
    let retries: Int
    let retryBaseDelaySeconds: Int
}

struct ResolvedConfig {
    let path: URL
    let table: TOMLTable

    let defaultsProvider: String
    let defaultsFrom: String
    let defaultsTo: String
    let defaultsPreset: String
    let defaultsFormat: FormatHint
    let defaultsYes: Bool
    let defaultsJobs: Int

    let network: NetworkRuntimeConfig

    let providers: [String: ProviderConfigEntry]
    let namedOpenAICompatible: [String: ProviderConfigEntry]
    let presets: [String: PresetDefinition]
}

enum InputMode: Sendable {
    case inlineText(String)
    case stdin(String)
    case files([ResolvedInputFile], cameFromGlob: Bool)
}

struct ResolvedInputFile: Sendable, Hashable {
    let path: URL
    let matchedByGlob: Bool
}

struct OutputTarget: Sendable {
    let source: ResolvedInputFile
    let destination: URL
    let inPlace: Bool
}

enum OutputMode: Sendable {
    case stdout
    case singleFile(URL)
    case perFile([OutputTarget], inPlace: Bool)
}

struct ResolvedPromptSet: Sendable {
    let systemPrompt: String
    let userPrompt: String
    let customPromptActive: Bool
}

struct TranslationInvocation: Sendable {
    let inputMode: InputMode
    let outputMode: OutputMode
    let providerName: String
    let providerID: ProviderID?
    let model: String?
    let baseURL: String?
    let apiKey: String?
    let from: NormalizedLanguage
    let to: NormalizedLanguage
    let formatHint: FormatHint
    let dryRun: Bool
    let quiet: Bool
    let verbose: Bool
    let noLang: Bool
    let yes: Bool
    let jobs: Int
    let suffix: String?
    let context: String
    let presetName: String
    let systemPromptOverride: String?
    let userPromptOverride: String?
}

struct FileInspection: Sendable {
    let file: ResolvedInputFile
    let content: String?
    let warning: String?
    let error: String?
}

struct TranslationFileResult: Sendable {
    let file: ResolvedInputFile
    let destination: URL?
    let success: Bool
    let errorMessage: String?
}
