import Foundation

enum MilestoneScope {
    static let deepLEnabled = false
}

enum PlatformBaseline {
    static let minimumMacOSMajor = 26
}

enum BuiltInDefaults {
    static let provider = "openai"
    static let from = "auto"
    static let to = "en"
    static let preset = "general"
    static let format = "auto"
    static let yes = false
    static let jobs = 1

    static let openAIModel = "gpt-4o-mini"
    static let anthropicModel = "claude-3-5-haiku-latest"
    static let ollamaModel = "llama3.2"

    static let openAIBaseURL = "https://api.openai.com"
    static let anthropicBaseURL = "https://api.anthropic.com"
    static let ollamaBaseURL = "http://localhost:11434"

    static let sourceLanguagePlaceholder = "the source language"
}

enum BuiltInNetwork {
    static let timeoutSeconds = 120
    static let retries = 3
    static let retryBaseDelaySeconds = 1
}
