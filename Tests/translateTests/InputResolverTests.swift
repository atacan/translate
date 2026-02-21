import XCTest
@testable import translate

final class InputResolverTests: XCTestCase {
    func testForceTextRequiresExactlyOneArgument() async {
        let terminal = TerminalIO(quiet: true, verbose: false)
        await XCTAssertThrowsErrorAsync(
            try await InputResolver().resolve(
                positional: ["a", "b"],
                forceText: true,
                terminal: terminal,
                cwd: URL(fileURLWithPath: "/tmp")
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.exitCode, .invalidArguments)
            XCTAssertEqual(appError.message, "--text requires exactly one positional argument.")
        }
    }

    func testSingleNonExistingPathIsInlineText() async throws {
        let terminal = TerminalIO(quiet: true, verbose: false)
        let result = try await InputResolver().resolve(
            positional: ["this-path-should-not-exist-\(UUID().uuidString)"],
            forceText: false,
            terminal: terminal,
            cwd: URL(fileURLWithPath: "/tmp")
        )

        guard case .inlineText(let text) = result else {
            return XCTFail("Expected inline text mode.")
        }
        XCTAssertTrue(text.hasPrefix("this-path-should-not-exist-"))
    }

    func testMultipleArgumentsRequireValidFiles() async {
        let terminal = TerminalIO(quiet: true, verbose: false)
        await XCTAssertThrowsErrorAsync(
            try await InputResolver().resolve(
                positional: ["/definitely/missing-1", "/definitely/missing-2"],
                forceText: false,
                terminal: terminal,
                cwd: URL(fileURLWithPath: "/tmp")
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(appError.exitCode, .invalidArguments)
            XCTAssertTrue(appError.message.contains("is not a valid file path"))
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    _ errorHandler: (_ error: Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
