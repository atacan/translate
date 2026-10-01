import XCTest
import CatalogTranslation
import StringCatalog
@testable import translate

final class CatalogIntegrityTests: XCTestCase {
    func testFormatArgumentsPermitPositionalReordering() throws {
        for (source, target) in [
            ("%@ has %lld files", "%2$lld fichiers pour %1$@"),
            ("%*.*f", "%3$*1$.*2$f"),
            ("% d %+.2f %#x", "%3$#x %2$+.2f %1$ d"),
            ("%02d %.3f %zu %qX %C %S %D %U %O", "%9$O %8$U %7$D %6$S %5$C %4$qX %3$zu %2$.3f %1$02d"),
            ("%#@item.count@ %@", "%2$@ %1$#@item.count@"),
            ("%1$@ %1$@ %%", "%% %1$@ %1$@"),
            ("%% %@ %@", "%2$@ %% %1$@"),
            ("Save 20%, 50% off, 100% sure, %-discount, 100% happy, 50% long-term", "Économisez 20 %, moitié prix, certainement, remise"),
            ("%@님 %d件", "%2$d件 %1$@님")
        ] { XCTAssertNoThrow(try CatalogFormatValidator.validate(source: source, translation: target), source) }
    }

    func testFormatArgumentsRejectLostAddedChangedAndDuplicateUses() {
        for (source, target) in [
            ("Hello %@", "Hello"), ("Hello", "Hello %@"), ("%d", "%f"),
            ("%lld", "%d"), ("% d", "%d"), ("%02d", "%d"), ("%.2f", "%.3f"),
            ("%@ %d", "%1$d %2$@"), ("%1$@", "%1$@ %1$@"),
            ("%1$@ %1$@", "%1$@"), ("%#@items@", "%#@other@"),
            ("100%% %@", "%@"), ("%%", "%% %%"),
            ("%*d %*d", "%2$*3$d %4$*1$d"),
            ("%*.*f", "%3$*2$.*1$f"), ("%#@items@ %@", "%1$@ %2$#@items@"),
            ("%@ %@", "%2$@ %@"), ("%*d", "%2$*d"), ("%.*f", "%2$.*f"),
            ("%#@items@ %@", "%#@items@ %2$@"),
            ("%@name", "name"), ("%@님", "님"), ("%d件", "件")
        ] { XCTAssertThrowsError(try CatalogFormatValidator.validate(source: source, translation: target), "\(source) -> \(target)") }
    }

    func testSelectionAndDryRunPlanMatchExecutionAcrossAllSegmentKinds() async throws {
        let source: [String: Any] = [
            "stringUnit": unit("Hello %@"),
            "stringSet": ["state": "translated", "values": ["First %d", "Second %@"]],
            "variations": ["plural": ["one": ["stringUnit": unit("One %d")], "other": ["stringUnit": unit("Many %d")]], "device": ["iphone": ["stringUnit": unit("Phone %@")]]],
            "substitutions": ["item.count": ["argNum": 1, "formatSpecifier": "lld", "variations": ["plural": ["one": ["stringUnit": unit("Sub %lld")]]]]]
        ]
        let target: [String: Any] = [
            "futureLocale": "keep", "stringUnit": unit("", "translated"),
            "stringSet": ["state": "new", "values": ["Old first", "Old second"], "futureSet": 7],
            "variations": ["plural": ["one": ["stringUnit": unit("Ancien %d", "needs_review")], "other": ["stringUnit": unit("Done %d")]], "device": ["iphone": ["stringUnit": unit("Phone old %@", "new")]]],
            "substitutions": ["item.count": ["argNum": 1, "formatSpecifier": "lld", "variations": ["plural": ["one": ["stringUnit": unit("Sub old %lld", "needs_review")]]]]]
        ]
        let file = try fixture(source: source, target: target, targetKey: "FR")
        let plan = try await prepare(file)
        XCTAssertEqual(plan.requests.count, 6)
        let translator = RecordingTranslator()
        let result = try await plan.translate(using: translator, jobs: 3)
        XCTAssertTrue(result.report.failures.isEmpty)
        let actualRequests = await translator.requests
        XCTAssertEqual(Set(plan.requests), Set(actualRequests))
        let output = try json(plan.encodedCatalog(result))
        let locale = try localization(output, "FR")
        XCTAssertNil(try localizations(output)["fr"])
        XCTAssertEqual(locale["futureLocale"] as? String, "keep")
        let set = try XCTUnwrap(locale["stringSet"] as? [String: Any])
        XCTAssertEqual(set["futureSet"] as? Int, 7)
        XCTAssertEqual(set["state"] as? String, "translated")
        let variations = try XCTUnwrap(locale["variations"] as? [String: Any])
        let plurals = try XCTUnwrap(variations["plural"] as? [String: Any])
        XCTAssertEqual(plurals["other"] as? NSDictionary, target["variations"].flatMap { ($0 as? [String: Any])?["plural"] }.flatMap { ($0 as? [String: Any])?["other"] } as? NSDictionary)
    }

    func testCompletedUnknownStatesPreservedAndForcedFailuresRestoreOriginals() async throws {
        let file = try fixture(source: ["stringUnit": unit("Hello %@")], target: ["stringUnit": unit("Bonjour %@", "future_complete"), "metadata": true])
        let defaultPlan = try await prepare(file)
        XCTAssertTrue(defaultPlan.requests.isEmpty)
        let forced = try await prepare(file, force: true)
        XCTAssertEqual(forced.requests.count, 1)
        let failed = try await forced.translate(using: FixedTranslator(value: "Invalid"), jobs: 1)
        XCTAssertEqual(failed.report.failures.count, 1)
        XCTAssertEqual(try localization(json(forced.encodedCatalog(failed)), "fr") as NSDictionary, ["stringUnit": unit("Bonjour %@", "future_complete"), "metadata": true] as NSDictionary)
        let valid = try await forced.translate(using: FixedTranslator(value: "Salut %1$@"), jobs: 1)
        XCTAssertEqual(valid.catalog.strings["entry"]?.localizations?["fr"]?.stringUnit?.value, "Salut %1$@")
    }

    func testVariantOnlyEntriesDoNotSynthesizeBaseAndOpaqueKeysSurvive() async throws {
        let file = try fixture(source: ["variations": ["device": ["future.device": ["stringUnit": unit("Device %@")]]], "substitutions": ["a.b": ["argNum": 2, "formatSpecifier": "lld", "variations": ["plural": ["other": ["stringUnit": unit("Sub %lld")]]]]]])
        let plan = try await prepare(file)
        XCTAssertEqual(plan.requests.count, 2)
        XCTAssertFalse(plan.requests.contains { $0.segment == .stringUnit })
        let result = try await plan.translate(using: RecordingTranslator(), jobs: 2)
        XCTAssertTrue(result.report.failures.isEmpty)
        let locale = try localization(json(plan.encodedCatalog(result)), "fr")
        XCTAssertNil(locale["stringUnit"])
        let substitutions = try XCTUnwrap(locale["substitutions"] as? [String: Any])
        XCTAssertEqual((substitutions["a.b"] as? [String: Any])?["argNum"] as? Int, 2)
    }

    func testPartialStringSetDoesNotCopySourceOrMarkFailedSlotsTranslated() async throws {
        for existing in [false, true] {
            let file = try fixture(source: ["stringSet": ["state": "translated", "values": ["Good %@", "Bad %d"]]], target: existing ? ["stringSet": ["state": "translated", "values": ["Old %@", "Old %d"]]] : nil)
            let plan = try await prepare(file, force: existing)
            let result = try await plan.translate(using: RecordingTranslator(failText: "Bad %d"), jobs: 2)
            XCTAssertEqual(result.report.failures.count, 1)
            XCTAssertNil(result.catalog.strings["entry"]?.localizations?["fr"]?.stringUnit)
            let set = try XCTUnwrap(try localization(json(plan.encodedCatalog(result)), "fr")["stringSet"] as? [String: Any])
            XCTAssertEqual(set["values"] as? [String], existing ? ["TR:Good %@", "Old %d"] : ["TR:Good %@", ""])
            XCTAssertEqual(set["state"] as? String, "needs_review")
        }
    }

    func testDefaultAndForcedSelectionPolicyForEverySegmentKind() async throws {
        for (state, value, expected) in [("translated", "Target %@", 0), ("future_complete", "Target %@", 0), ("new", "Target %@", 6), ("needs_review", "Target %@", 6), ("translated", "", 6)] {
            let file = try fixture(source: allSegments("Source %@"), target: allSegments(value, state: state))
            let normal = try await prepare(file)
            XCTAssertEqual(normal.requests.count, expected, "State \(state), value \(value)")
            let forced = try await prepare(file, force: true)
            XCTAssertEqual(forced.requests.count, 6)
        }
    }

    func testForcedFailuresPreserveEveryOriginalSlotAndMetadata() async throws {
        let target = allSegments("Original %@")
        let file = try fixture(source: allSegments("Source %@"), target: target)
        let plan = try await prepare(file, force: true)
        let result = try await plan.translate(using: FixedTranslator(value: "Lost placeholder"), jobs: 3)
        XCTAssertEqual(result.report.failures.count, 6)
        let output = try json(plan.encodedCatalog(result))
        XCTAssertEqual(try localization(output, "fr") as NSDictionary, target as NSDictionary)
        XCTAssertEqual(output["rootMetadata"] as? String, "keep")
    }

    private func allSegments(_ value: String, state: String = "translated") -> [String: Any] {
        let variation: [String: Any] = ["stringUnit": unit(value, state), "variationMetadata": true]
        let variants: [String: Any] = ["plural": ["other": variation], "device": ["iphone": variation]]
        return ["stringUnit": unit(value, state), "stringSet": ["state": state, "values": [value], "setMetadata": 42], "variations": variants, "substitutions": ["a.b": ["argNum": 1, "formatSpecifier": "@", "variations": variants, "subMetadata": "keep"]], "localeMetadata": true]
    }

    func testSourceLanguageGuardPreservesSourceAndRejectsForcedRetranslation() async throws {
        let file = try fixture(source: ["stringUnit": unit("Hello %@"), "stringSet": ["state": "new", "values": ["Source %d"]]])
        let language = NormalizedLanguage(input: "EN", displayName: "English", providerCode: "EN", isAuto: false)
        let plan = try await CatalogPendingPlan.prepare(file: file, targetLanguage: language, jobs: 1)
        XCTAssertTrue(plan.requests.isEmpty)
        let translator = RecordingTranslator()
        let result = try await plan.translate(using: translator, jobs: 1)
        let calls = await translator.requests
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(try json(plan.encodedCatalog(result)) as NSDictionary, try json(String(contentsOf: file.path, encoding: .utf8)) as NSDictionary)
        do { _ = try await CatalogPendingPlan.prepare(file: file, targetLanguage: language, jobs: 1, retranslate: true); XCTFail("Expected source guard") }
        catch { XCTAssertTrue(String(describing: error).contains("sourceLanguage")) }
    }

    private func unit(_ value: String, _ state: String = "translated") -> [String: Any] { ["state": state, "value": value, "unitMetadata": "keep"] }
    private func fixture(source: [String: Any], target: [String: Any]? = nil, targetKey: String = "fr") throws -> ResolvedInputFile {
        let url = try TestSupport.makeTemporaryDirectory().appendingPathComponent("Localizable.xcstrings")
        var locales: [String: Any] = ["en": source]
        if let target { locales[targetKey] = target }
        let data = try JSONSerialization.data(withJSONObject: ["sourceLanguage": "en", "version": "1.0", "rootMetadata": "keep", "strings": ["entry": ["entryMetadata": true, "localizations": locales]]])
        try data.write(to: url)
        return ResolvedInputFile(path: url, matchedByGlob: false)
    }
    private func prepare(_ file: ResolvedInputFile, force: Bool = false) async throws -> CatalogPendingPlan {
        try await CatalogPendingPlan.prepare(file: file, targetLanguage: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false), jobs: 2, retranslate: force)
    }
    private func json(_ string: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any]) }
    private func localizations(_ object: [String: Any]) throws -> [String: Any] {
        let strings = try XCTUnwrap(object["strings"] as? [String: Any]); let entry = try XCTUnwrap(strings["entry"] as? [String: Any]); return try XCTUnwrap(entry["localizations"] as? [String: Any])
    }
    private func localization(_ object: [String: Any], _ key: String) throws -> [String: Any] { try XCTUnwrap(localizations(object)[key] as? [String: Any]) }
}

private actor RecordingTranslator: CatalogTextTranslator {
    var requests: [TranslationRequest] = []
    let failText: String?
    init(failText: String? = nil) { self.failText = failText }
    func translate(_ request: TranslationRequest) async throws -> String {
        requests.append(request)
        if request.text == failText { return "Invalid" }
        return "TR:" + request.text
    }
}
private struct FixedTranslator: CatalogTextTranslator {
    let value: String
    func translate(_ request: TranslationRequest) async throws -> String { value }
}
