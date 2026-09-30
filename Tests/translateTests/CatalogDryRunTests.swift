import XCTest
import Foundation
@testable import translate

final class CatalogDryRunTests: XCTestCase {
    func testMixedDryRunShowsBothPathsAndNeverConfirmsOrWrites() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory)
        let text = directory.appendingPathComponent("notes.md")
        try "Text body".write(to: text, atomically: true, encoding: .utf8)
        let original = try Data(contentsOf: catalog)
        let output = try run(directory: directory, arguments: ["--dry-run", "--in-place", "--to", "fr", text.path, catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("File: \(text.path)"))
        XCTAssertTrue(output.stdout.contains("File: \(catalog.path)"))
        XCTAssertTrue(output.stdout.contains("Preset: general"))
        XCTAssertTrue(output.stdout.contains("Preset: xcode-strings"))
        XCTAssertTrue(output.stdout.contains("Pending segments: 1"))
        XCTAssertTrue(output.stdout.contains("Xcode string catalog"))
        XCTAssertTrue(output.stdout.contains("Developer comment: Button label"))
        XCTAssertTrue(output.stdout.contains("built-in preset xcode-strings"))
        XCTAssertFalse(output.stderr.contains("Proceed?"))
        XCTAssertEqual(try Data(contentsOf: catalog), original)
        XCTAssertEqual(try String(contentsOf: text, encoding: .utf8), "Text body")
    }

    func testCatalogDryRunHandlesZeroPendingAndMalformedCatalog() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory, translated: true)
        var output = try run(directory: directory, arguments: ["--dry-run", "--to", "fr", catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("Pending segments: 0"))
        XCTAssertTrue(output.stdout.contains("No pending segments"))
        try "{\"strings\":{}}".write(to: catalog, atomically: true, encoding: .utf8)
        output = try run(directory: directory, arguments: ["--dry-run", "--to", "fr", catalog.path])
        XCTAssertNotEqual(output.status, 0)
        XCTAssertTrue(output.stderr.contains("Invalid catalog"))
        XCTAssertTrue(output.stderr.contains("sourceLanguage"))
    }

    func testExplicitGeneralAndCustomizedGeneralMetadataWinForCatalogs() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory)
        let configURL = directory.appendingPathComponent("config.toml")
        try "[defaults]\npreset = 'general'\n".write(to: configURL, atomically: true, encoding: .utf8)
        var output = try run(directory: directory, arguments: ["--dry-run", "--to", "fr", catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("Preset: general"))
        XCTAssertFalse(output.stdout.contains("Xcode string catalog"))
        try "[presets.general]\nprovider = 'ollama'\nmodel = 'custom-model'\nto = 'de'\nfrom = 'it'\nformat = 'html'\n".write(to: configURL, atomically: true, encoding: .utf8)
        output = try run(directory: directory, arguments: ["--dry-run", catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("Preset: general"))
        XCTAssertTrue(output.stdout.contains("Model: custom-model"))
        XCTAssertTrue(output.stdout.contains("German (de)"))
        XCTAssertTrue(output.stdout.contains("English (en); catalog sourceLanguage"))
        XCTAssertTrue(output.stdout.contains("Translate the following HTML from English to German"))
        XCTAssertTrue(output.stderr.contains("overrides configured source 'Italian (it)'"))
        XCTAssertTrue(output.stderr.contains("affects segment {format} only"))
    }

    func testMixedDefaultsPreserveCatalogPresetMetadata() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory)
        let text = directory.appendingPathComponent("notes.txt")
        try "Hello".write(to: text, atomically: true, encoding: .utf8)
        try "[presets.xcode-strings]\nprovider = 'ollama'\nmodel = 'catalog-model'\nto = 'de'\n".write(to: directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let output = try run(directory: directory, arguments: ["--dry-run", text.path, catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        let parts = output.stdout.components(separatedBy: "=== CATALOG DRY RUN ===")
        XCTAssertTrue(parts[0].contains("Preset: general"))
        XCTAssertTrue(parts[0].contains("Provider:       openai"))
        XCTAssertTrue(parts[0].contains("Target lang:    English"))
        XCTAssertTrue(parts.last?.contains("Provider: ollama") == true)
        XCTAssertTrue(parts.last?.contains("Model: catalog-model") == true)
        XCTAssertTrue(parts.last?.contains("Target lang: German (de)") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Localizable_DE.xcstrings").path))
    }

    func testPromptlessCatalogSkipsUnusedFilesAndWarnsAboutPromptPortionOnly() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory)
        try "[presets.custom]\nprovider = 'deepl'\nto = 'fr'\nuser_prompt_file = 'missing.txt'\n".write(to: directory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let output = try run(directory: directory, arguments: ["--dry-run", "--preset", "custom", "--system-prompt", "@also-missing.txt", catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("Provider: deepl"))
        XCTAssertTrue(output.stdout.contains("Target lang: French (fr)"))
        XCTAssertTrue(output.stdout.contains("unused (promptless provider)"))
        XCTAssertTrue(output.stderr.contains("prompt portion of --preset"))
        XCTAssertTrue(output.stderr.contains("preset metadata still applies"))
        XCTAssertFalse(output.stderr.contains("not found"))
    }

    func testRetranslateFlagSelectsCompletedTargetsAndAppliesOnlyToCatalogs() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory, translated: true)
        let text = directory.appendingPathComponent("notes.txt")
        try "Hello".write(to: text, atomically: true, encoding: .utf8)
        let output = try run(directory: directory, arguments: ["--dry-run", "--retranslate", "--to", "fr", text.path, catalog.path])
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("Mode: text translation"))
        XCTAssertTrue(output.stdout.contains("Pending segments: 1"))
        XCTAssertEqual(try String(contentsOf: text, encoding: .utf8), "Hello")
        for arguments in [["--dry-run", "--retranslate", "--text", "Hello"], ["--dry-run", "--retranslate", text.path]] {
            let invalid = try run(directory: directory, arguments: arguments)
            XCTAssertNotEqual(invalid.status, 0)
            XCTAssertTrue(invalid.stderr.contains("--retranslate requires at least one .xcstrings catalog"))
        }
    }

    func testRetranslateExecutionAttemptsCompletedTargetAndPreservesItOnFailure() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory, translated: true)
        // Port zero cannot accept a connection; no external service is contacted.
        let provider = ["--provider", "openai-compatible", "--model", "mock", "--api-key", "test", "--base-url", "http://127.0.0.1:0", "--to", "fr"]
        let completed = try run(directory: directory, arguments: provider + [catalog.path])
        XCTAssertEqual(completed.status, 0, completed.stderr)
        let forced = try run(directory: directory, arguments: ["--retranslate"] + provider + [catalog.path])
        XCTAssertNotEqual(forced.status, 0)
        XCTAssertTrue(forced.stderr.contains("segment(s) failed in catalog translation"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(forced.stdout.utf8)) as? [String: Any])
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["greeting"] as? [String: Any])
        let locales = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let target = try XCTUnwrap(locales["fr"] as? [String: Any])
        XCTAssertEqual((target["stringUnit"] as? [String: Any])?["value"] as? String, "Bonjour")
    }

    func testSourceTargetCLIHasNoPendingRequestsAndRejectsForce() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        let catalog = try writeCatalog(in: directory)
        let normal = try run(directory: directory, arguments: ["--dry-run", "--to", "EN", catalog.path])
        XCTAssertEqual(normal.status, 0, normal.stderr)
        XCTAssertTrue(normal.stdout.contains("Pending segments: 0"))
        let forced = try run(directory: directory, arguments: ["--dry-run", "--retranslate", "--to", "EN", catalog.path])
        XCTAssertNotEqual(forced.status, 0)
        XCTAssertTrue(forced.stderr.contains("cannot target catalog sourceLanguage"))
    }

    private func writeCatalog(in directory: URL, translated: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent("Localizable.xcstrings")
        let target = translated ? ",\"fr\":{\"stringUnit\":{\"state\":\"translated\",\"value\":\"Bonjour\"}}" : ""
        try "{\"sourceLanguage\":\"en\",\"strings\":{\"greeting\":{\"comment\":\"Button label\",\"localizations\":{\"en\":{\"stringUnit\":{\"state\":\"translated\",\"value\":\"Hello\"}}\(target)}}},\"version\":\"1.0\"}".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func run(directory: URL, arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let configURL = directory.appendingPathComponent("config.toml")
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try "".write(to: configURL, atomically: true, encoding: .utf8)
        }
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("translate")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--config", directory.appendingPathComponent("config.toml").path] + arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
