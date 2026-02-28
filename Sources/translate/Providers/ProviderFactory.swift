import Foundation

struct ProviderSelection {
    let name: String
    let id: ProviderID?
    let provider: any TranslationProvider
    let model: String?
    let baseURL: String?
    let apiKey: String?
    let promptless: Bool
    let warnings: [String]
}

struct ProviderFactory {
    let config: ResolvedConfig
    let env: [String: String]

    func make(
        providerName: String,
        modelOverride: String?,
        baseURLOverride: String?,
        apiKeyOverride: String?,
        explicitProvider: Bool,
        requireCredentials: Bool = true
    ) throws -> ProviderSelection {
        let lowerName = providerName.lowercased()

        if ProviderID.builtInNames.contains(lowerName) {
            guard let id = ProviderID(rawValue: lowerName) else {
                throw AppError.invalidArguments("Unknown provider '\(providerName)'. Run translate --help for valid providers.")
            }
            return try makeBuiltIn(
                id: id,
                modelOverride: modelOverride,
                baseURLOverride: baseURLOverride,
                apiKeyOverride: apiKeyOverride,
                explicitProvider: explicitProvider,
                requireCredentials: requireCredentials
            )
        }

        if let named = config.namedOpenAICompatible[providerName] {
            let baseURL = baseURLOverride ?? named.baseURL
            let model = modelOverride ?? named.model
            let apiKey = apiKeyOverride ?? named.apiKey

            guard let baseURL, !baseURL.isEmpty else {
                throw AppError.invalidArguments("--base-url is required when using openai-compatible.")
            }
            guard let model, !model.isEmpty else {
                throw AppError.invalidArguments("--model is required when using openai-compatible.")
            }
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: API key is required for provider 'openai-compatible'.")
            }

            let provider = AnyLanguageModelTextProvider(
                id: .openAICompatible,
                backend: .openAICompatible,
                baseURL: baseURL,
                model: model,
                apiKey: apiKey
            )
            return ProviderSelection(name: providerName, id: nil, provider: provider, model: model, baseURL: baseURL, apiKey: apiKey, promptless: false, warnings: [])
        }

        throw AppError.invalidArguments("Unknown provider '\(providerName)'. Run translate --help for valid providers.")
    }

    private func makeBuiltIn(
        id: ProviderID,
        modelOverride: String?,
        baseURLOverride: String?,
        apiKeyOverride: String?,
        explicitProvider: Bool,
        requireCredentials: Bool
    ) throws -> ProviderSelection {
        switch id {
        case .openai:
            if explicitProvider && baseURLOverride != nil {
                throw AppError.invalidArguments("--base-url cannot be used with --provider openai. It is only valid for openai-compatible providers.")
            }
            let cfg = config.providers[id.rawValue]
            let model = modelOverride ?? cfg?.model ?? BuiltInDefaults.openAIModel
            let baseURL = cfg?.baseURL ?? BuiltInDefaults.openAIBaseURL
            let apiKey = apiKeyOverride ?? cfg?.apiKey ?? env["OPENAI_API_KEY"]
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: OPENAI_API_KEY is required for provider 'openai'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnyLanguageModelTextProvider(
                    id: id,
                    backend: .openai,
                    baseURL: baseURL,
                    model: model,
                    apiKey: apiKey
                ),
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                promptless: false,
                warnings: []
            )

        case .anthropic:
            if explicitProvider && baseURLOverride != nil {
                throw AppError.invalidArguments("--base-url cannot be used with --provider anthropic. It is only valid for openai-compatible providers.")
            }
            let cfg = config.providers[id.rawValue]
            let model = modelOverride ?? cfg?.model ?? BuiltInDefaults.anthropicModel
            let baseURL = cfg?.baseURL ?? BuiltInDefaults.anthropicBaseURL
            let apiKey = apiKeyOverride ?? cfg?.apiKey ?? env["ANTHROPIC_API_KEY"]
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: ANTHROPIC_API_KEY is required for provider 'anthropic'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnyLanguageModelTextProvider(
                    id: id,
                    backend: .anthropic,
                    baseURL: baseURL,
                    model: model,
                    apiKey: apiKey
                ),
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                promptless: false,
                warnings: []
            )

        case .gemini:
            let cfg = config.providers[id.rawValue]
            let model = modelOverride ?? cfg?.model ?? BuiltInDefaults.geminiModel
            let baseURL = baseURLOverride ?? cfg?.baseURL ?? BuiltInDefaults.geminiBaseURL
            let apiKey = apiKeyOverride ?? cfg?.apiKey ?? env["GEMINI_API_KEY"]
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: GEMINI_API_KEY is required for provider 'gemini'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnyLanguageModelTextProvider(
                    id: id,
                    backend: .gemini,
                    baseURL: baseURL,
                    model: model,
                    apiKey: apiKey
                ),
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                promptless: false,
                warnings: []
            )

        case .openResponses:
            let cfg = config.providers[id.rawValue]
            let model = modelOverride ?? cfg?.model ?? BuiltInDefaults.openResponsesModel
            let baseURL = baseURLOverride ?? cfg?.baseURL ?? BuiltInDefaults.openResponsesBaseURL
            let apiKey = apiKeyOverride ?? cfg?.apiKey ?? env["OPEN_RESPONSES_API_KEY"]
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: OPEN_RESPONSES_API_KEY is required for provider 'open-responses'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnyLanguageModelTextProvider(
                    id: id,
                    backend: .openResponses,
                    baseURL: baseURL,
                    model: model,
                    apiKey: apiKey
                ),
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                promptless: false,
                warnings: []
            )

        case .ollama:
            if explicitProvider && baseURLOverride != nil {
                throw AppError.invalidArguments("--base-url cannot be used with --provider ollama. It is only valid for openai-compatible providers.")
            }
            let cfg = config.providers[id.rawValue]
            let model = modelOverride ?? cfg?.model ?? BuiltInDefaults.ollamaModel
            let baseURL = cfg?.baseURL ?? BuiltInDefaults.ollamaBaseURL
            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnyLanguageModelTextProvider(
                    id: id,
                    backend: .ollama,
                    baseURL: baseURL,
                    model: model,
                    apiKey: nil
                ),
                model: model,
                baseURL: baseURL,
                apiKey: nil,
                promptless: false,
                warnings: []
            )

        case .openAICompatible:
            let cfg = config.providers[id.rawValue]
            let model = modelOverride ?? cfg?.model
            let baseURL = baseURLOverride ?? cfg?.baseURL
            let apiKey = apiKeyOverride ?? cfg?.apiKey

            guard let baseURL, !baseURL.isEmpty else {
                throw AppError.invalidArguments("--base-url is required when using openai-compatible.")
            }
            guard let model, !model.isEmpty else {
                throw AppError.invalidArguments("--model is required when using openai-compatible.")
            }
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: API key is required for provider 'openai-compatible'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnyLanguageModelTextProvider(
                    id: id,
                    backend: .openAICompatible,
                    baseURL: baseURL,
                    model: model,
                    apiKey: apiKey
                ),
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                promptless: false,
                warnings: []
            )

        case .appleIntelligence:
            if modelOverride != nil {
                throw AppError.invalidArguments("--model is not applicable for apple-intelligence. This provider uses the system model.")
            }
            if explicitProvider && baseURLOverride != nil {
                throw AppError.invalidArguments("--base-url cannot be used with --provider apple-intelligence. It is only valid for openai-compatible providers.")
            }
            if apiKeyOverride != nil {
                throw AppError.invalidArguments("--api-key is not applicable for apple-intelligence.")
            }
            try AppleIntelligenceProvider.validateAvailability()
            return ProviderSelection(name: id.rawValue, id: id, provider: AppleIntelligenceProvider(), model: nil, baseURL: nil, apiKey: nil, promptless: false, warnings: [])

        case .appleTranslate:
            if modelOverride != nil {
                throw AppError.invalidArguments("--model is not applicable for apple-translate. This provider does not use a model.")
            }
            if explicitProvider && baseURLOverride != nil {
                throw AppError.invalidArguments("--base-url cannot be used with --provider apple-translate. It is only valid for openai-compatible providers.")
            }
            if apiKeyOverride != nil {
                throw AppError.invalidArguments("--api-key is not applicable for apple-translate.")
            }
            try AppleTranslateProvider.validateAvailability()
            return ProviderSelection(name: id.rawValue, id: id, provider: AppleTranslateProvider(), model: nil, baseURL: nil, apiKey: nil, promptless: true, warnings: [])

        case .deepl:
            if modelOverride != nil {
                throw AppError.invalidArguments("--model is not applicable for deepl. This provider does not use a model.")
            }
            if explicitProvider && baseURLOverride != nil {
                throw AppError.invalidArguments("--base-url cannot be used with --provider deepl. It is only valid for openai-compatible providers.")
            }

            let cfg = config.providers[id.rawValue]
            let apiKey = apiKeyOverride ?? cfg?.apiKey ?? env["DEEPL_API_KEY"]
            guard !requireCredentials || (apiKey?.isEmpty == false) else {
                throw AppError.runtime("Error: DEEPL_API_KEY is required for provider 'deepl'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: DeepLProvider(apiKey: apiKey ?? ""),
                model: nil,
                baseURL: nil,
                apiKey: apiKey,
                promptless: true,
                warnings: []
            )
        }
    }
}
