import Foundation

struct OutputPlanningRequest {
    let inputMode: InputMode
    let toLanguage: NormalizedLanguage
    let outputPath: String?
    let inPlace: Bool
    let suffix: String?
    let cwd: URL
}

struct OutputPlanningResult {
    let mode: OutputMode
    let warnings: [String]
}

struct OutputPlanner {
    func plan(_ request: OutputPlanningRequest) throws -> OutputPlanningResult {
        var warnings: [String] = []

        if request.inPlace && request.outputPath != nil {
            throw AppError.invalidArguments("--in-place and --output cannot be used together.")
        }

        if request.inPlace && request.suffix != nil {
            throw AppError.invalidArguments("--in-place and --suffix cannot be used together. --in-place overwrites the original file; --suffix creates a new file.")
        }

        switch request.inputMode {
        case .inlineText, .stdin:
            if request.inPlace {
                throw AppError.invalidArguments("--in-place requires file input.")
            }
            if let outputPath = request.outputPath {
                return OutputPlanningResult(mode: .singleFile(resolvePath(outputPath, cwd: request.cwd)), warnings: warnings)
            }
            return OutputPlanningResult(mode: .stdout, warnings: warnings)

        case .files(let files, let cameFromGlob):
            let hasMultiple = files.count > 1
            let anyGlob = cameFromGlob || files.contains(where: \.matchedByGlob)

            if request.outputPath != nil && (hasMultiple || anyGlob) {
                throw AppError.invalidArguments("--output can only be used with a single input. Use --suffix for multiple files.")
            }

            if request.inPlace {
                let targets = files.map { file in
                    OutputTarget(source: file, destination: file.path, inPlace: true)
                }
                return OutputPlanningResult(mode: .perFile(targets, inPlace: true), warnings: warnings)
            }

            if let outputPath = request.outputPath {
                return OutputPlanningResult(mode: .singleFile(resolvePath(outputPath, cwd: request.cwd)), warnings: warnings)
            }

            let singleExplicitFileToStdout = files.count == 1 && !anyGlob
            if singleExplicitFileToStdout {
                if request.suffix != nil {
                    warnings.append("Warning: --suffix has no effect when outputting to stdout. Use --output to write to a file.")
                }
                return OutputPlanningResult(mode: .stdout, warnings: warnings)
            }

            let suffix = request.suffix ?? "_\(request.toLanguage.outputSuffixCode)"
            let targets = files.map { file in
                let destination = file.path.deletingLastPathComponent()
                    .appendingPathComponent(applySuffix(sourceFileName: file.path.lastPathComponent, suffix: suffix))
                return OutputTarget(source: file, destination: destination, inPlace: false)
            }
            return OutputPlanningResult(mode: .perFile(targets, inPlace: false), warnings: warnings)
        }
    }

    private func resolvePath(_ path: String, cwd: URL) -> URL {
        let url = URL(fileURLWithPath: path)
        if url.path.hasPrefix("/") {
            return url.standardizedFileURL
        }
        return cwd.appendingPathComponent(path).standardizedFileURL
    }

    private func applySuffix(sourceFileName: String, suffix: String) -> String {
        guard let dot = sourceFileName.lastIndex(of: ".") else {
            return sourceFileName + suffix
        }

        let stem = String(sourceFileName[..<dot])
        let ext = String(sourceFileName[dot...])
        return stem + suffix + ext
    }
}
