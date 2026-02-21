import XCTest
@testable import translate

final class CLITests: XCTestCase {
    func testRunHelpContainsCoreOptions() {
        let help = TranslateCommand.helpMessage(for: TranslateRunCommand.self, columns: 120)
        XCTAssertTrue(help.contains("--dry-run"))
        XCTAssertTrue(help.contains("--provider"))
        XCTAssertTrue(help.contains("--format"))
    }

    func testRootHelpContainsSubcommands() {
        let help = TranslateCommand.helpMessage(columns: 120)
        XCTAssertTrue(help.contains("SUBCOMMANDS:"))
        XCTAssertTrue(help.contains("config"))
        XCTAssertTrue(help.contains("presets"))
    }
}
