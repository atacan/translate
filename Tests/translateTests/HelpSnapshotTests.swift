import XCTest
@testable import translate

final class HelpSnapshotTests: XCTestCase {
    func testTranslateRunHelpSnapshotCoreSections() {
        let help = TranslateCommand.helpMessage(for: TranslateRunCommand.self, columns: 100)
        XCTAssertTrue(help.contains("USAGE:"))
        XCTAssertTrue(help.contains("ARGUMENTS:"))
        XCTAssertTrue(help.contains("OPTIONS:"))
    }

    func testSubcommandHelpSnapshotCoreSections() {
        let configHelp = TranslateCommand.helpMessage(for: ConfigCommand.self, columns: 100)
        XCTAssertTrue(configHelp.contains("USAGE:"))
        XCTAssertTrue(configHelp.contains("SUBCOMMANDS:"))

        let presetsHelp = TranslateCommand.helpMessage(for: PresetsCommand.self, columns: 100)
        XCTAssertTrue(presetsHelp.contains("USAGE:"))
        XCTAssertTrue(presetsHelp.contains("SUBCOMMANDS:"))
    }
}
