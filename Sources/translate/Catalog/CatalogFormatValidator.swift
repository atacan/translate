import Foundation

/// Compare argument uses, not their textual order. Explicit positions let a translator
/// reorder arguments while retaining the original format and argument contract.
enum CatalogFormatValidator {
    private struct Use: Hashable {
        let position: Int
        let format: String
    }

    static func validate(source: String, translation: String) throws {
        guard let sourceUses = scan(source), let translatedUses = scan(translation), sourceUses == translatedUses else {
            throw AppError.runtime("Catalog format placeholders changed (identity, type, argument position, or multiplicity).")
        }
    }

    private static func scan(_ text: String) -> [Use: Int]? {
        let chars = Array(text)
        var uses: [Use: Int] = [:]
        var nextArgument = 1
        var hasImplicitArguments = false
        var hasExplicitArguments = false
        var index = 0
        func digit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
        func argument(_ explicit: Int?) -> Int {
            if let explicit { hasExplicitArguments = true; return explicit }
            hasImplicitArguments = true
            defer { nextArgument += 1 }
            return nextArgument
        }
        while index < chars.count {
            guard chars[index] == "%" else { index += 1; continue }
            let start = index
            index += 1
            if index < chars.count, chars[index] == "%" {
                uses[Use(position: 0, format: "%%"), default: 0] += 1
                index += 1; continue
            }
            var cursor = index
            func position() -> Int? {
                let begin = cursor
                while cursor < chars.count && digit(chars[cursor]) { cursor += 1 }
                if cursor > begin, cursor < chars.count, chars[cursor] == "$",
                   let value = Int(String(chars[begin..<cursor])), value > 0 {
                    cursor += 1
                    return value
                }
                cursor = begin
                return nil
            }
            let explicit = position()
            // Xcode named substitutions retain both their name and argument position.
            if cursor + 1 < chars.count, chars[cursor] == "#", chars[cursor + 1] == "@" {
                let begin = cursor + 2
                cursor = begin
                while cursor < chars.count && chars[cursor] != "@" { cursor += 1 }
                if cursor < chars.count, cursor > begin {
                    let name = String(chars[begin..<cursor])
                    uses[Use(position: argument(explicit), format: "#@\(name)@"), default: 0] += 1
                    index = cursor + 1
                    continue
                }
            }
            cursor = index
            let valuePosition = position()
            let flagsBegin = cursor
            while cursor < chars.count && "-+ #0'".contains(chars[cursor]) { cursor += 1 }
            let flags = String(chars[flagsBegin..<cursor])
            var width = ""
            var widthPosition: Int?
            var precision = ""
            var precisionPosition: Int?
            if cursor < chars.count && chars[cursor] == "*" {
                width = "*"; cursor += 1; widthPosition = position()
            } else {
                let begin = cursor
                while cursor < chars.count && digit(chars[cursor]) { cursor += 1 }
                width = String(chars[begin..<cursor])
            }
            if cursor < chars.count && chars[cursor] == "." {
                cursor += 1
                precision = "."
                if cursor < chars.count && chars[cursor] == "*" {
                    precision += "*"; cursor += 1; precisionPosition = position()
                } else {
                    let begin = cursor
                    while cursor < chars.count && digit(chars[cursor]) { cursor += 1 }
                    precision += String(chars[begin..<cursor])
                }
            }
            var length = ""
            if cursor + 1 < chars.count && ["hh", "ll"].contains(String(chars[cursor...cursor + 1])) {
                length = String(chars[cursor...cursor + 1]); cursor += 2
            } else if cursor < chars.count && "hljztLq".contains(chars[cursor]) {
                length = String(chars[cursor]); cursor += 1
            }
            guard cursor < chars.count, "diouxXfFeEgGaAcCsSpn@DUO".contains(chars[cursor]) else { continue }
            let conversion = chars[cursor]
            // Percent prose often starts a natural word with a printf letter:
            // “50% off”, “100% sure”, “%-discount”. A following letter identifies
            // that word. Unicode suffixes and object placeholders remain formats.
            let hasGrammar = valuePosition != nil || !width.isEmpty || !precision.isEmpty || ["ll", "hh"].contains(length)
            let validLength: Bool
            switch length {
            case "h", "hh", "ll", "q", "j", "z", "t": validLength = "diouxXn".contains(conversion)
            case "l": validLength = "diouxXnfFeEgGaAcs".contains(conversion)
            case "L": validLength = "fFeEgGaA".contains(conversion)
            default: validLength = true
            }
            guard validLength else { continue }
            let followedByLetter = cursor + 1 < chars.count && chars[cursor + 1].isASCII && chars[cursor + 1].isLetter
            if conversion != "@" && followedByLetter && !hasGrammar { continue }
            if start > 0 && chars[start - 1].isNumber && flags.contains(" ") && !hasGrammar { continue }
            if width == "*" {
                let position = argument(widthPosition)
                width = "*arg\(position)"
            }
            if precision == ".*" {
                let position = argument(precisionPosition)
                precision = ".*arg\(position)"
            }
            let normalizedFlags = String(Set(flags).sorted())
            uses[Use(position: argument(valuePosition), format: normalizedFlags + width + precision + length + String(conversion)), default: 0] += 1
            index = cursor + 1
        }
        // printf forbids mixing sequential and numbered argument consumption,
        // including width/precision stars. Escaped percents consume neither.
        return hasImplicitArguments && hasExplicitArguments ? nil : uses
    }
}
