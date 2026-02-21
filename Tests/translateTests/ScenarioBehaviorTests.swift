import XCTest
@testable import translate

final class ScenarioBehaviorTests: XCTestCase {
    func testScenarioInlineTextResolvesToInlineMode() async throws {
        let terminal = TerminalIO(quiet: true, verbose: false)
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let inputMode = try await InputResolver().resolve(
            positional: ["Bonjour le monde"],
            forceText: false,
            terminal: terminal,
            cwd: cwd
        )

        guard case .inlineText(let text) = inputMode else {
            return XCTFail("Expected inline text mode.")
        }
        XCTAssertEqual(text, "Bonjour le monde")
    }

    func testScenarioForceTextTreatsExistingPathAsText() async throws {
        let terminal = TerminalIO(quiet: true, verbose: false)
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let existingFile = cwd.appendingPathComponent("document.md")
        try "Hello".write(to: existingFile, atomically: true, encoding: .utf8)

        let inputMode = try await InputResolver().resolve(
            positional: ["document.md"],
            forceText: true,
            terminal: terminal,
            cwd: cwd
        )

        guard case .inlineText(let text) = inputMode else {
            return XCTFail("Expected inline text mode when --text is used.")
        }
        XCTAssertEqual(text, "document.md")
    }

    func testScenarioSingleExplicitFileDefaultsToStdout() async throws {
        let terminal = TerminalIO(quiet: true, verbose: false)
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let existingFile = cwd.appendingPathComponent("file.md")
        try "Hello".write(to: existingFile, atomically: true, encoding: .utf8)

        let inputMode = try await InputResolver().resolve(
            positional: ["file.md"],
            forceText: false,
            terminal: terminal,
            cwd: cwd
        )

        let planned = try OutputPlanner().plan(
            OutputPlanningRequest(
                inputMode: inputMode,
                toLanguage: language(code: "fr", input: "fr", displayName: "French"),
                outputPath: nil,
                inPlace: false,
                suffix: nil,
                cwd: cwd
            )
        )

        if case .stdout = planned.mode {
            return
        }
        XCTFail("Expected stdout output mode for a single explicit file.")
    }

    func testScenarioSingleMatchGlobWritesPerFileOutput() async throws {
        let terminal = TerminalIO(quiet: true, verbose: false)
        let cwd = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let existingFile = cwd.appendingPathComponent("file.md")
        try "Hello".write(to: existingFile, atomically: true, encoding: .utf8)

        let inputMode = try await InputResolver().resolve(
            positional: ["*.md"],
            forceText: false,
            terminal: terminal,
            cwd: cwd
        )

        let planned = try OutputPlanner().plan(
            OutputPlanningRequest(
                inputMode: inputMode,
                toLanguage: language(code: "fr", input: "fr", displayName: "French"),
                outputPath: nil,
                inPlace: false,
                suffix: nil,
                cwd: cwd
            )
        )

        guard case .perFile(let targets, let inPlace) = planned.mode else {
            return XCTFail("Expected per-file output for glob input.")
        }

        XCTAssertFalse(inPlace)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].destination.lastPathComponent, "file_FR.md")
    }

    func testScenarioMultiFileSuffixUsesInsertedSuffix() throws {
        let fileA = ResolvedInputFile(path: URL(fileURLWithPath: "/tmp/a.md"), matchedByGlob: true)
        let fileB = ResolvedInputFile(path: URL(fileURLWithPath: "/tmp/b.md"), matchedByGlob: true)

        let planned = try OutputPlanner().plan(
            OutputPlanningRequest(
                inputMode: .files([fileA, fileB], cameFromGlob: true),
                toLanguage: language(code: "fr", input: "fr", displayName: "French"),
                outputPath: nil,
                inPlace: false,
                suffix: ".fr",
                cwd: URL(fileURLWithPath: "/tmp")
            )
        )

        guard case .perFile(let targets, _) = planned.mode else {
            return XCTFail("Expected per-file output for multi-file glob input.")
        }

        XCTAssertEqual(targets.map { $0.destination.lastPathComponent }.sorted(), ["a.fr.md", "b.fr.md"])
    }

    private func language(code: String, input: String, displayName: String) -> NormalizedLanguage {
        NormalizedLanguage(input: input, displayName: displayName, providerCode: code, isAuto: false)
    }
}
