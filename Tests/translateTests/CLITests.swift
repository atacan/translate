import XCTest
@testable import translate

final class CLITests: XCTestCase {
    func testRootHelpContainsCoreOptionsAndSubcommands() {
        let help = TranslateHelp.root
        XCTAssertTrue(help.contains("--dry-run"))
        XCTAssertTrue(help.contains("--provider"))
        XCTAssertTrue(help.contains("--format"))
        XCTAssertTrue(help.contains("SUBCOMMANDS:"))
        XCTAssertTrue(help.contains("config"))
        XCTAssertTrue(help.contains("presets"))
    }
}
