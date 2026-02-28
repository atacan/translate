import XCTest
@testable import translate

final class CLITests: XCTestCase {
    func testRootHelpContainsCoreOptionsAndSubcommands() {
        let help = TranslateHelp.root
        XCTAssertTrue(help.contains("--dry-run"))
        XCTAssertTrue(help.contains("--stream"))
        XCTAssertTrue(help.contains("--no-stream"))
        XCTAssertTrue(help.contains("--provider"))
        XCTAssertTrue(help.contains("--format"))
        XCTAssertTrue(help.contains("SUBCOMMANDS:"))
        XCTAssertTrue(help.contains("config"))
        XCTAssertTrue(help.contains("presets"))
    }

    func testRunCommandParsesStreamFlag() throws {
        let command = try XCTUnwrap(
            try TranslateRunCommand.parseAsRoot(["--stream", "--text", "hello"]) as? TranslateRunCommand
        )
        XCTAssertTrue(command.options.stream)
    }

    func testRunCommandParsesNoStreamFlag() throws {
        let command = try XCTUnwrap(
            try TranslateRunCommand.parseAsRoot(["--no-stream", "--text", "hello"]) as? TranslateRunCommand
        )
        XCTAssertTrue(command.options.noStream)
    }
}
