import Foundation

struct LanguageNormalizer {
    private static let englishLocale = Locale(identifier: "en")

    private static let iso639_2To1: [String: String] = [
        "fra": "fr", "fre": "fr", "deu": "de", "ger": "de", "spa": "es", "ita": "it",
        "por": "pt", "zho": "zh", "chi": "zh", "jpn": "ja", "kor": "ko", "rus": "ru",
        "tur": "tr", "nld": "nl", "dut": "nl", "pol": "pl", "ukr": "uk", "ron": "ro",
        "rum": "ro", "ces": "cs", "cze": "cs", "ara": "ar", "hin": "hi", "swe": "sv",
        "dan": "da", "fin": "fi", "nor": "no", "ell": "el", "gre": "el", "heb": "he",
    ]

    private static let languageNameToCode: [String: String] = {
        var map: [String: String] = [:]
        for code in languageCodes {
            if let name = englishLocale.localizedString(forLanguageCode: code) {
                map[name.lowercased()] = code
            }
        }
        map["chinese (traditional)"] = "zh-TW"
        map["traditional chinese"] = "zh-TW"
        map["chinese (simplified)"] = "zh-CN"
        map["simplified chinese"] = "zh-CN"
        return map
    }()

    static func normalizeFrom(_ raw: String) throws -> NormalizedLanguage {
        try normalize(raw, allowAuto: true)
    }

    static func normalizeTo(_ raw: String) throws -> NormalizedLanguage {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto" {
            throw AppError.invalidArguments("'auto' is not valid for --to. A specific target language is required. Example: --to fr")
        }
        return try normalize(raw, allowAuto: false)
    }

    private static func normalize(_ rawValue: String, allowAuto: Bool) throws -> NormalizedLanguage {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()

        if lowered == "auto" {
            guard allowAuto else {
                throw AppError.invalidArguments("'auto' is not valid for --to. A specific target language is required. Example: --to fr")
            }
            return NormalizedLanguage(input: raw, displayName: BuiltInDefaults.sourceLanguagePlaceholder, providerCode: "auto", isAuto: true)
        }

        if let code = iso639_2To1[lowered], let normalized = fromLanguageCode(code, raw: raw) {
            return normalized
        }

        if let code = languageNameToCode[lowered], let normalized = fromLanguageCode(code, raw: raw) {
            return normalized
        }

        if let normalized = fromLanguageCode(lowered, raw: raw) {
            return normalized
        }

        if lowered.contains("-") {
            let parts = lowered.split(separator: "-")
            if let first = parts.first, first.count == 2,
               let name = displayName(forIdentifier: lowered, languageCode: String(first))
            {
                return NormalizedLanguage(input: raw, displayName: name, providerCode: lowered, isAuto: false)
            }
        }

        throw AppError.invalidArguments("'\(rawValue)' is not a recognized language. Use a language name (e.g. 'French'), ISO 639-1 code (e.g. 'fr'), or BCP 47 tag (e.g. 'zh-TW').")
    }

    private static func fromLanguageCode(_ candidate: String, raw: String) -> NormalizedLanguage? {
        if languageCodes.contains(candidate) {
            if let name = englishLocale.localizedString(forLanguageCode: candidate) {
                return NormalizedLanguage(input: raw, displayName: name, providerCode: candidate, isAuto: false)
            }
        }
        return nil
    }

    private static let languageCodes: Set<String> = Set(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))

    private static func displayName(forIdentifier identifier: String, languageCode: String) -> String? {
        if identifier.lowercased().hasPrefix("zh-tw") {
            return "Traditional Chinese"
        }
        if identifier.lowercased().hasPrefix("zh-cn") {
            return "Simplified Chinese"
        }
        if let identifierName = englishLocale.localizedString(forIdentifier: identifier) {
            return identifierName
        }
        return englishLocale.localizedString(forLanguageCode: languageCode)
    }
}
