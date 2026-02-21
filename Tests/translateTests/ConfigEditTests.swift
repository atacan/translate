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

    func testMakeProcessBuildsExpectedCommand() throws {
        let process = try ConfigEditor.makeProcess(editor: "vim", configPath: "/tmp/config.toml")
        XCTAssertEqual(process.executableURL?.path, "/usr/bin/env")
        XCTAssertEqual(process.arguments, ["vim", "/tmp/config.toml"])
    }

    func testMakeProcessSplitsEditorArguments() throws {
        let process = try ConfigEditor.makeProcess(editor: "code --wait", configPath: "/tmp/config.toml")
        XCTAssertEqual(process.arguments, ["code", "--wait", "/tmp/config.toml"])
    }

    func testMakeProcessHonorsQuotedEditorToken() throws {
        let process = try ConfigEditor.makeProcess(editor: "'Visual Studio Code' --wait", configPath: "/tmp/config.toml")
        XCTAssertEqual(process.arguments, ["Visual Studio Code", "--wait", "/tmp/config.toml"])
    }

    func testMakeProcessRejectsMalformedEditorCommand() {
        XCTAssertThrowsError(try ConfigEditor.makeProcess(editor: "\"unterminated", configPath: "/tmp/config.toml")) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.exitCode, .runtimeError)
            XCTAssertEqual(appError.message, "Invalid EDITOR command: unmatched escape or quote.")
        }
    }
}
