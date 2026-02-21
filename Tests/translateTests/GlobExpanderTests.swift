import XCTest
@testable import translate

final class GlobExpanderTests: XCTestCase {
    func testExpandMatchesAbsoluteGlobPattern() async throws {
        let temp = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let inputFile = temp.appendingPathComponent("note.md")
        try "hello".write(to: inputFile, atomically: true, encoding: .utf8)

        let unrelatedCWD = temp.appendingPathComponent("cwd")
        try FileManager.default.createDirectory(at: unrelatedCWD, withIntermediateDirectories: true)

        let matches = try await GlobExpander.expand(pattern: "\(temp.path)/*.md", cwd: unrelatedCWD)
        XCTAssertEqual(matches, [inputFile.standardizedFileURL])
    }

    func testExpandMatchesPrefixedRelativePattern() async throws {
        let temp = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let docs = temp.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

        let file = docs.appendingPathComponent("intro.md")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let matches = try await GlobExpander.expand(pattern: "docs/*.md", cwd: temp)
        XCTAssertEqual(matches, [file.standardizedFileURL])
    }
}
