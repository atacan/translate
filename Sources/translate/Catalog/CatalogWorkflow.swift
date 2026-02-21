import Foundation
import CatalogTranslation
import StringCatalog

struct CatalogWorkflow {
    func translateCatalogFile(
        file: ResolvedInputFile,
        targetLanguage: NormalizedLanguage,
        provider: any TranslationProvider,
        jobs: Int,
        outputMode: OutputMode,
        destinationMap: [ResolvedInputFile: URL],
        writer: OutputWriter,
        terminal: TerminalIO,
        network: NetworkRuntimeConfig
    ) async -> TranslationFileResult {
        do {
            let sourceCatalog = try StringCatalog(contentsOf: file.path)
            let targetCode = LanguageCode(rawValue: targetLanguage.providerCode)
            let translator = CatalogBridge.makeTranslator(
                provider: provider,
                timeoutSeconds: network.timeoutSeconds,
                network: network
            )
            let engine = CatalogTranslationEngine(
                translator: translator,
                options: TranslationOptions(maxConcurrentRequests: jobs)
            )

            let translation = try await engine.translateCatalog(sourceCatalog, to: targetCode, mode: .bestEffort)
            let encoded = try translation.catalog.encodePrettyToString()

            let destination = try write(
                text: encoded,
                for: file,
                outputMode: outputMode,
                destinationMap: destinationMap,
                writer: writer,
                terminal: terminal
            )

            if translation.report.failures.isEmpty {
                return TranslationFileResult(file: file, destination: destination, success: true, errorMessage: nil)
            }

            let firstFailureReason = translation.report.failures.first?.reason ?? "unknown failure"
            let summary = "\(translation.report.failures.count) segment(s) failed in catalog translation. First failure: \(firstFailureReason)"
            return TranslationFileResult(file: file, destination: destination, success: false, errorMessage: summary)
        } catch {
            return TranslationFileResult(file: file, destination: nil, success: false, errorMessage: error.localizedDescription)
        }
    }

    func dryRunDescription(
        providerName: String,
        model: String?,
        targetLanguage: NormalizedLanguage,
        jobs: Int,
        files: [ResolvedInputFile]
    ) -> String {
        let modelLine = model ?? "n/a"
        let fileList = files.map { "- \($0.path.path)" }.joined(separator: "\n")
        return """
        --- DRY RUN ---
        Mode: .xcstrings catalog translation
        Provider: \(providerName)
        Model: \(modelLine)
        Target language: \(targetLanguage.displayName) (\(targetLanguage.providerCode))
        Max concurrent catalog requests: \(max(1, jobs))
        Files:
        \(fileList)
        """
    }

    private func write(
        text: String,
        for file: ResolvedInputFile,
        outputMode: OutputMode,
        destinationMap: [ResolvedInputFile: URL],
        writer: OutputWriter,
        terminal: TerminalIO
    ) throws -> URL? {
        switch outputMode {
        case .stdout:
            terminal.writeStdout(text)
            return nil
        case .singleFile(let destination):
            try writer.writeFile(text: text, destination: destination)
            return destination
        case .perFile:
            guard let destination = destinationMap[file] else {
                throw AppError.runtime("No output target was planned for this file.")
            }
            try writer.writeFile(text: text, destination: destination)
            return destination
        }
    }
}
