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
        explicitProvider: Bool
    ) throws -> ProviderSelection {
        let lowerName = providerName.lowercased()

        if ProviderID.builtInNames.contains(lowerName) {
            guard let id = ProviderID(rawValue: lowerName) else {
                throw AppError.invalidArguments("Unknown provider '\(providerName)'. Run translate --help for valid providers.")
            }
            return try makeBuiltIn(id: id, modelOverride: modelOverride, baseURLOverride: baseURLOverride, apiKeyOverride: apiKeyOverride, explicitProvider: explicitProvider)
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

            let provider = OpenAICompatibleProvider(
                id: .openAICompatible,
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                httpClient: HTTPClient()
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
        explicitProvider: Bool
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
            guard let apiKey, !apiKey.isEmpty else {
                throw AppError.runtime("Error: OPENAI_API_KEY is required for provider 'openai'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: OpenAICompatibleProvider(id: id, baseURL: baseURL, model: model, apiKey: apiKey, httpClient: HTTPClient()),
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
            guard let apiKey, !apiKey.isEmpty else {
                throw AppError.runtime("Error: ANTHROPIC_API_KEY is required for provider 'anthropic'.")
            }

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: AnthropicProvider(baseURL: baseURL, model: model, apiKey: apiKey, httpClient: HTTPClient()),
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
                provider: OpenAICompatibleProvider(id: id, baseURL: baseURL, model: model, apiKey: nil, httpClient: HTTPClient()),
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

            return ProviderSelection(
                name: id.rawValue,
                id: id,
                provider: OpenAICompatibleProvider(id: id, baseURL: baseURL, model: model, apiKey: apiKey, httpClient: HTTPClient()),
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                promptless: false,
                warnings: []
            )

        case .appleIntelligence:
            if apiKeyOverride != nil {
                throw AppError.invalidArguments("--api-key is not applicable for apple-intelligence.")
            }
            return ProviderSelection(name: id.rawValue, id: id, provider: AppleIntelligenceProvider(), model: nil, baseURL: nil, apiKey: nil, promptless: false, warnings: [])

        case .appleTranslate:
            if modelOverride != nil {
                throw AppError.invalidArguments("--model is not applicable for apple-translate. This provider does not use a model.")
            }
            if apiKeyOverride != nil {
                throw AppError.invalidArguments("--api-key is not applicable for apple-translate.")
            }
            return ProviderSelection(name: id.rawValue, id: id, provider: AppleTranslateProvider(), model: nil, baseURL: nil, apiKey: nil, promptless: true, warnings: [])

        case .deepl:
            if !MilestoneScope.deepLEnabled {
                throw AppError.runtime("Error: Provider 'deepl' is deferred for this milestone.")
            }
            throw AppError.runtime("Error: Provider 'deepl' is not implemented yet.")
        }
    }
}
