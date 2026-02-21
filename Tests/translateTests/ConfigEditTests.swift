import XCTest
@testable import translate

final class ConfigEditTests: XCTestCase {
    func testResolvedEditorUsesEDITORWhenSet() {
        let editor = ConfigEditor.resolvedEditor(environment: ["EDITOR": "nano"])
        XCTAssertEqual(editor, "nano")
    }

    func testResolvedEditorFallsBackWhenEDITORMissingOrEmpty() {
        XCTAssertEqual(
            ConfigEditor.resolvedEditor(environment: [:], defaultEditor: "vi"),
            "vi"
        )
        XCTAssertEqual(
            ConfigEditor.resolvedEditor(environment: ["EDITOR": "   "], defaultEditor: "notepad"),
            "notepad"
        )
    }

    func testMakeProcessBuildsExpectedCommand() {
        let process = ConfigEditor.makeProcess(editor: "vim", configPath: "/tmp/config.toml")
        XCTAssertEqual(process.executableURL?.path, "/usr/bin/env")
        XCTAssertEqual(process.arguments, ["vim", "/tmp/config.toml"])
    }
}
