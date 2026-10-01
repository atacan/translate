import Foundation
import CatalogTranslation
import StringCatalog

/// Adapt selection to the public engine, then merge only successful slots into the
/// original JSON. The engine still owns requests, concurrency, and failure reporting.
struct CatalogPendingPlan: Sendable {
    let catalog: StringCatalog
    let targetLanguage: LanguageCode
    let requests: [TranslationRequest]
    private let prepared: StringCatalog
    private let original: JSONValue
    private let slots: [SlotKey: Slot]

    private struct SlotKey: Hashable, Sendable {
        let key: String
        let segment: TranslationSegment
    }
    private struct Slot: Sendable {
        let path: [String]
        let index: Int?
        let substitutionSource: JSONValue?
    }

    static func prepare(file: ResolvedInputFile, targetLanguage: NormalizedLanguage, jobs: Int, retranslate: Bool = false) async throws -> Self {
        let data = try Data(contentsOf: file.path)
        let catalog: StringCatalog
        let original: JSONValue
        do {
            catalog = try JSONDecoder().decode(StringCatalog.self, from: data)
            original = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch let error as DecodingError {
            throw AppError.runtime("Invalid catalog '\(file.path.path)': \(String(describing: error)). Check the .xcstrings JSON structure and required sourceLanguage, strings, and version fields.")
        }
        let target = LanguageCode(rawValue: targetLanguage.providerCode)
        if target.rawValue.caseInsensitiveCompare(catalog.sourceLanguage.rawValue) == .orderedSame {
            if retranslate { throw AppError.invalidArguments("--retranslate cannot target catalog sourceLanguage '\(catalog.sourceLanguage.rawValue)'; source localizations are preserved.") }
            return Self(catalog: catalog, targetLanguage: target, requests: [], prepared: catalog, original: original, slots: [:])
        }
        var document = original
        var slots: [SlotKey: Slot] = [:]
        for (key, entry) in original.object["strings"]?.object ?? [:] {
            if entry.object["shouldTranslate"] == .bool(false) { continue }
            let localizations = entry.object["localizations"]?.object ?? [:]
            let source = localizations[catalog.sourceLanguage.rawValue] ?? .object([:])
            let targetKey = localizations[target.rawValue] != nil ? target.rawValue
                : localizations.keys.first { $0.caseInsensitiveCompare(target.rawValue) == .orderedSame } ?? target.rawValue
            let prefix = ["strings", key, "localizations", targetKey]
            func selectUnit(_ relative: [String], segment: TranslationSegment, substitution: JSONValue? = nil) {
                let path = prefix + relative
                let existing = original.value(at: path)
                let value = existing?.object["value"]?.text ?? ""
                let state = existing?.object["state"]?.text ?? ""
                if existing == nil || value.isEmpty || retranslate || ["new", "needs_review"].contains(state) {
                    if existing != nil {
                        if case .variation = segment { document.set(.string(""), at: path + ["value"]) }
                        else { document.set(nil, at: path) }
                    }
                    slots[SlotKey(key: key, segment: segment)] = Slot(path: path, index: nil, substitutionSource: substitution)
                }
            }
            let sourceUnit = source.object["stringUnit"]
            let variantOnly = sourceUnit == nil && ["stringSet", "variations", "substitutions"].contains { source.object[$0] != nil }
            if variantOnly {
                // Stop the dependency synthesizing a base request from the string key.
                document.set(.object(["state": .string("translated"), "value": .string(key)]), at: prefix + ["stringUnit"])
            } else {
                selectUnit(["stringUnit"], segment: .stringUnit)
            }
            if let values = source.object["stringSet"]?.object["values"]?.array {
                let path = prefix + ["stringSet"]
                let existing = original.value(at: path)
                var targetValues = existing?.object["values"]?.array ?? []
                while targetValues.count < values.count { targetValues.append(.string("")) }
                let state = existing?.object["state"]?.text ?? ""
                for (index, value) in values.enumerated() where value.text?.isEmpty == false {
                    if targetValues[index].text?.isEmpty != false || retranslate || ["new", "needs_review"].contains(state) {
                        targetValues[index] = .string("")
                        slots[SlotKey(key: key, segment: .stringSet(index: index))] = Slot(path: path, index: index, substitutionSource: nil)
                    }
                }
                document.set(.object(["state": .string(state.isEmpty ? "needs_review" : state), "values": .array(targetValues)]), at: path)
            }
            func selectVariations(_ variations: JSONValue?, relative: [String], publicPrefix: String, substitution: JSONValue? = nil) {
                for kind in ["device", "plural"] {
                    for (variant, value) in variations?.object[kind]?.object ?? [:] where value.object["stringUnit"]?.object["value"]?.text?.isEmpty == false {
                        selectUnit(relative + [kind, variant, "stringUnit"], segment: .variation(path: "\(publicPrefix).\(kind).\(variant)"), substitution: substitution)
                    }
                }
            }
            selectVariations(source.object["variations"], relative: ["variations"], publicPrefix: "variations")
            for (name, substitution) in source.object["substitutions"]?.object ?? [:] {
                selectVariations(substitution.object["variations"], relative: ["substitutions", name, "variations"], publicPrefix: "substitutions.\(name).variations", substitution: substitution)
            }
        }
        let prepared = try JSONDecoder().decode(StringCatalog.self, from: JSONEncoder().encode(document))
        let recorder = CatalogRequestRecorder()
        _ = try await CatalogTranslationEngine(translator: recorder, options: TranslationOptions(maxConcurrentRequests: jobs))
            .translateCatalog(prepared, to: target, mode: .bestEffort)
        let requests = await recorder.requests.sorted {
            ($0.stringKey, CatalogBridge.segmentLabel($0.segment)) < ($1.stringKey, CatalogBridge.segmentLabel($1.segment))
        }
        return Self(catalog: catalog, targetLanguage: target, requests: requests, prepared: prepared, original: original, slots: slots)
    }

    func translate(using translator: any CatalogTextTranslator, jobs: Int) async throws -> CatalogTranslationResult {
        if requests.isEmpty { return CatalogTranslationResult(catalog: catalog, report: TranslationReport(stats: TranslationStats(), failures: [])) }
        let result = try await CatalogTranslationEngine(translator: ValidatingCatalogTranslator(base: translator), options: TranslationOptions(maxConcurrentRequests: jobs))
            .translateCatalog(prepared, to: targetLanguage, mode: .bestEffort)
        let document = try reconciled(result)
        return CatalogTranslationResult(catalog: try JSONDecoder().decode(StringCatalog.self, from: JSONEncoder().encode(document)), report: result.report)
    }

    /// Encode from original JSON so fields outside the dependency's model survive.
    func encodedCatalog(_ result: CatalogTranslationResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(reconciled(result)), as: UTF8.self)
    }

    private func reconciled(_ result: CatalogTranslationResult) throws -> JSONValue {
        let translated = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(result.catalog))
        let failures = Set(result.report.failures.map { SlotKey(key: $0.stringKey, segment: $0.segment) })
        var document = original
        var sets: [[String]: Bool] = [:]
        var successfulSets: Set<[String]> = []
        for request in requests {
            let key = SlotKey(key: request.stringKey, segment: request.segment)
            guard let slot = slots[key] else { continue }
            if let index = slot.index {
                if failures.contains(key) { sets[slot.path] = false; continue }
                var set = document.value(at: slot.path)?.object ?? [:]
                var values = set["values"]?.array ?? []
                let sourceCount = translated.value(at: slot.path)?.object["values"]?.array?.count ?? index + 1
                while values.count < max(sourceCount, index + 1) { values.append(.string("")) }
                guard let newValues = translated.value(at: slot.path)?.object["values"]?.array, newValues.indices.contains(index) else { continue }
                values[index] = newValues[index]
                set["values"] = .array(values)
                document.set(.object(set), at: slot.path)
                successfulSets.insert(slot.path)
                if sets[slot.path] == nil { sets[slot.path] = true }
            } else if !failures.contains(key), let value = translated.value(at: slot.path)?.object["value"] {
                // A missing substitution needs its argNum/formatSpecifier, but must
                // not inherit source variation values for failed sibling segments.
                if let source = slot.substitutionSource, let offset = slot.path.indices.dropFirst(4).first(where: { slot.path[$0] == "substitutions" }) {
                    let substitutionPath = Array(slot.path.prefix(offset + 2))
                    if document.value(at: substitutionPath) == nil {
                        var metadata = source.object
                        metadata.removeValue(forKey: "variations")
                        document.set(.object(metadata), at: substitutionPath)
                    }
                }
                var unit = document.value(at: slot.path)?.object ?? [:]
                unit["value"] = value
                unit["state"] = .string("translated")
                document.set(.object(unit), at: slot.path)
            }
        }
        for (path, succeeded) in sets {
            if succeeded { document.set(.string("translated"), at: path + ["state"]) }
            else if successfulSets.contains(path) {
                // A partial set cannot claim completion, even in forced mode when
                // the original completed value of a failed slot was retained.
                let oldState = original.value(at: path + ["state"])?.text
                document.set(.string(oldState == "new" || oldState == "needs_review" ? oldState! : "needs_review"), at: path + ["state"])
            }
        }
        return document
    }

    func sourceWarnings(configuredSource: NormalizedLanguage, filename: String) -> [String] {
        guard !configuredSource.isAuto,
              configuredSource.providerCode.caseInsensitiveCompare(catalog.sourceLanguage.rawValue) != .orderedSame else { return [] }
        return ["\(filename): catalog sourceLanguage '\(catalog.sourceLanguage.englishDisplayName) (\(catalog.sourceLanguage.rawValue))' overrides configured source '\(configuredSource.displayName) (\(configuredSource.providerCode))'. --from and preset/config source settings do not change catalog source selection."]
    }
}

private struct ValidatingCatalogTranslator: CatalogTextTranslator {
    let base: any CatalogTextTranslator
    func translate(_ request: TranslationRequest) async throws -> String {
        let text = try await base.translate(request)
        try CatalogFormatValidator.validate(source: request.text, translation: text)
        return text
    }
}

private actor CatalogRequestRecorder: CatalogTextTranslator {
    private(set) var requests: [TranslationRequest] = []
    func translate(_ request: TranslationRequest) async throws -> String { requests.append(request); return request.text }
}

private extension JSONValue {
    var object: [String: JSONValue] { if case .object(let value) = self { return value }; return [:] }
    var array: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
    var text: String? { if case .string(let value) = self { return value }; return nil }
    func value(at path: [String]) -> JSONValue? {
        if path.isEmpty { return self }
        return object[path[0]]?.value(at: Array(path.dropFirst()))
    }
    mutating func set(_ value: JSONValue?, at path: [String]) {
        guard let first = path.first else { if let value { self = value }; return }
        var fields = object
        if path.count == 1 { fields[first] = value }
        else {
            var child = fields[first] ?? .object([:])
            child.set(value, at: Array(path.dropFirst()))
            fields[first] = child
        }
        self = .object(fields)
    }
}
