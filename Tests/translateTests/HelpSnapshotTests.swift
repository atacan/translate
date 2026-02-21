import XCTest
@testable import translate

final class HelpSnapshotTests: XCTestCase {
    func testRootHelpSnapshotMatchesSpecSection16() {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specPath = testsDirectory.appendingPathComponent("translate-cli-spec.md")
        let expected = try! String(contentsOf: specPath, encoding: .utf8)
        let helpSection = expected.components(separatedBy: "## 16. Help Text").last ?? ""
        let normalizedSection = helpSection.replacingOccurrences(of: "→", with: "->")
        XCTAssertTrue(normalizedSection.contains(TranslateHelp.root))
    }

    func testConfigSubcommandHelpSnapshotContainsExpectedActions() {
        let configHelp = TranslateCommand.helpMessage(for: ConfigCommand.self, columns: 100)
        XCTAssertTrue(configHelp.contains("USAGE:"))
        XCTAssertTrue(configHelp.contains("SUBCOMMANDS:"))
        XCTAssertTrue(configHelp.contains("show"))
        XCTAssertTrue(configHelp.contains("path"))
        XCTAssertTrue(configHelp.contains("get"))
        XCTAssertTrue(configHelp.contains("set"))
        XCTAssertTrue(configHelp.contains("unset"))
        XCTAssertTrue(configHelp.contains("edit"))
    }

    func testPresetsSubcommandHelpSnapshotContainsExpectedActions() {
        let presetsHelp = TranslateCommand.helpMessage(for: PresetsCommand.self, columns: 100)
        XCTAssertTrue(presetsHelp.contains("USAGE:"))
        XCTAssertTrue(presetsHelp.contains("SUBCOMMANDS:"))
        XCTAssertTrue(presetsHelp.contains("list"))
        XCTAssertTrue(presetsHelp.contains("show"))
        XCTAssertTrue(presetsHelp.contains("which"))
    }
}
