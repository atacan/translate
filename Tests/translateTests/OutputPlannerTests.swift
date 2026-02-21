import XCTest
@testable import translate

final class OutputPlannerTests: XCTestCase {
    func testSuffixWarningForSingleExplicitFileToStdout() throws {
        let file = ResolvedInputFile(path: URL(fileURLWithPath: "/tmp/input.md"), matchedByGlob: false)
        let result = try OutputPlanner().plan(
            OutputPlanningRequest(
                inputMode: .files([file], cameFromGlob: false),
                toLanguage: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false),
                outputPath: nil,
                inPlace: false,
                suffix: ".translated",
                cwd: URL(fileURLWithPath: "/tmp")
            )
        )

        if case .stdout = result.mode {
        } else {
            XCTFail("Expected stdout mode for single explicit file.")
        }
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(
            result.warnings.first,
            "Warning: --suffix has no effect when outputting to stdout. Use --output to write to a file."
        )
    }

    func testOutputConflictMessageForGlobInput() {
        let file = ResolvedInputFile(path: URL(fileURLWithPath: "/tmp/input.md"), matchedByGlob: true)
        XCTAssertThrowsError(
            try OutputPlanner().plan(
                OutputPlanningRequest(
                    inputMode: .files([file], cameFromGlob: true),
                    toLanguage: NormalizedLanguage(input: "fr", displayName: "French", providerCode: "fr", isAuto: false),
                    outputPath: "out.md",
                    inPlace: false,
                    suffix: nil,
                    cwd: URL(fileURLWithPath: "/tmp")
                )
            )
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError.")
            }
            XCTAssertEqual(
                appError.message,
                "--output can only be used with a single input. Use --suffix to control output filenames for multiple files."
            )
            XCTAssertEqual(appError.exitCode, .invalidArguments)
        }
    }
}
