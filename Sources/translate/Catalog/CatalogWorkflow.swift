import Foundation
import CatalogTranslation
import StringCatalog

struct CatalogWorkflow {
    func translateCatalogFile(
        file: ResolvedInputFile,
        targetLanguage: NormalizedLanguage,
        prompts: CatalogPromptConfiguration? = nil,
        plan: CatalogPendingPlan? = nil,
        retranslate: Bool = false,
        provider: any TranslationProvider,
        jobs: Int,
        outputMode: OutputMode,
        destinationMap: [ResolvedInputFile: URL],
        writer: OutputWriter,
        terminal: TerminalIO,
        network: NetworkRuntimeConfig
    ) async -> TranslationFileResult {
        do {
            let pendingPlan: CatalogPendingPlan
            if let plan { pendingPlan = plan }
            else { pendingPlan = try await CatalogPendingPlan.prepare(file: file, targetLanguage: targetLanguage, jobs: jobs, retranslate: retranslate) }
            let resolvedPrompts: CatalogPromptConfiguration
            if let prompts { resolvedPrompts = prompts }
            else {
                let preset = BuiltInPresetStore.all()["xcode-strings"]!
                let templates = try PromptRenderer().resolvePrompts(
                    preset: preset, systemPromptOverride: nil, userPromptOverride: nil,
                    cwd: file.path.deletingLastPathComponent(), noLang: false
                ).0
                resolvedPrompts = CatalogPromptConfiguration(
                    templates: templates, context: "", filename: file.path.lastPathComponent, format: .text
                )
            }
            let translator = CatalogBridge.makeTranslator(provider: provider, prompts: resolvedPrompts, network: network)

            // Confirm an overwrite before any request is sent, then save progress to the
            // destination as segments finish. An interrupted run loses at most the last
            // checkpoint interval, and an in-place rerun resumes from what was saved.
            let destination = try plannedDestination(for: file, outputMode: outputMode, destinationMap: destinationMap)
            if let destination { try writer.confirmOverwriteIfNeeded(destination: destination) }
            var onCheckpoint: (@Sendable (String) async throws -> Void)?
            if let destination {
                onCheckpoint = { @Sendable text in try OutputWriter.writeAtomically(text: text, destination: destination) }
            }

            let translation = try await pendingPlan.translate(
                using: translator,
                jobs: jobs,
                maxConsecutiveFailures: CatalogBridge.maxConsecutiveFailures(jobs: jobs),
                checkpointPolicy: Self.checkpointPolicy,
                onCheckpoint: onCheckpoint
            )
            let encoded = try pendingPlan.encodedCatalog(translation)

            if let destination {
                try OutputWriter.writeAtomically(text: encoded, destination: destination)
            } else {
                terminal.writeStdout(encoded)
            }

            let report = translation.report
            if report.failures.isEmpty && report.abort == nil {
                return TranslationFileResult(file: file, destination: destination, success: true, errorMessage: nil)
            }
            return TranslationFileResult(
                file: file, destination: destination, success: false,
                errorMessage: Self.failureSummary(report, destination: destination, file: file, outputMode: outputMode, targetLanguage: targetLanguage)
            )
        } catch {
            return TranslationFileResult(file: file, destination: nil, success: false, errorMessage: (error as? AppError)?.message ?? error.localizedDescription)
        }
    }

    func dryRunDescription(
        file: ResolvedInputFile,
        plan: CatalogPendingPlan,
        providerName: String,
        model: String?,
        presetName: String,
        presetOrigin: String,
        targetOrigin: String,
        origins: PromptOrigins,
        prompts: CatalogPromptConfiguration,
        promptless: Bool,
        jobs: Int,
        network: NetworkRuntimeConfig
    ) -> String {
        var lines = [
            "=== CATALOG DRY RUN ===",
            "File: \(file.path.path)",
            "Mode: .xcstrings catalog translation (per segment)",
            "Preset: \(presetName)",
            "Preset origin: \(presetOrigin)",
            "Source lang: \(plan.catalog.sourceLanguage.englishDisplayName) (\(plan.catalog.sourceLanguage.rawValue)); catalog sourceLanguage",
            "Target lang: \(plan.targetLanguage.englishDisplayName) (\(plan.targetLanguage.rawValue))",
            "Target origin: \(targetOrigin)",
            "Provider: \(providerName)",
            "Model: \(model ?? "(provider default)")",
            "System prompt origin: \(promptless ? "unused (promptless provider)" : origins.system)",
            "User prompt origin: \(promptless ? "unused (promptless provider)" : origins.user)",
            "Max concurrent catalog requests: \(max(1, jobs))",
            "Pending segments: \(plan.requests.count)"
        ]
        if plan.requests.isEmpty {
            lines.append("No pending segments; no translation requests would be sent.")
        }
        // Show a bounded sample of real requests, including at least one segment for every file.
        for request in plan.requests.prefix(3) {
            let rendered = prompts.providerRequest(for: request, network: network)
            lines.append("String key: \(request.stringKey); segment: \(CatalogBridge.segmentLabel(request.segment))")
            lines.append(DryRunPrinter.render(
                provider: providerName, model: model, from: rendered.from, to: rendered.to,
                prompts: ResolvedPromptSet(systemPrompt: rendered.systemPrompt ?? "", userPrompt: rendered.userPrompt ?? "", customPromptActive: prompts.templates.customPromptActive),
                inputText: request.text
            ))
        }
        if plan.requests.count > 3 { lines.append("Showing 3 of \(plan.requests.count) pending segment requests.") }
        return lines.joined(separator: "\n")
    }

    static let checkpointPolicy = TranslationCheckpointPolicy(everySegments: 25, interval: 5)

    static func failureSummary(
        _ report: TranslationReport,
        destination: URL?,
        file: ResolvedInputFile,
        outputMode: OutputMode,
        targetLanguage: NormalizedLanguage
    ) -> String {
        var parts: [String] = []
        let stats = report.stats
        if let abort = report.abort {
            let cause: String
            switch abort.cause {
            case .fatalError: cause = "Stopped early after an error that would fail every remaining segment"
            case .consecutiveFailures(let count): cause = "Stopped early after \(count) segment(s) failed in a row"
            }
            parts.append("\(cause): \(abort.reason). \(stats.translatedSegments) of \(stats.attemptedSegments) segment(s) translated; \(stats.skippedSegments) not attempted.")
        }
        if !report.failures.isEmpty {
            let details = report.failures.map { failure in
                "'\(failure.stringKey)' (\(CatalogBridge.segmentLabel(failure.segment))): \(failure.reason)"
            }.joined(separator: "; ")
            parts.append("\(report.failures.count) segment(s) failed in catalog translation. \(details)")
        }
        if let destination, stats.translatedSegments > 0 || report.abort != nil {
            var inPlace = false
            if case .perFile(_, true) = outputMode { inPlace = true }
            if inPlace || destination.standardizedFileURL == file.path.standardizedFileURL {
                parts.append("Translated segments were saved; rerun the same command to translate only the remaining segments.")
            } else {
                parts.append("Translated segments were saved to '\(destination.path)'. To translate only the remaining segments, run: translate --in-place --to \(targetLanguage.providerCode) '\(destination.path)'")
            }
        }
        return parts.joined(separator: " ")
    }

    private func plannedDestination(
        for file: ResolvedInputFile,
        outputMode: OutputMode,
        destinationMap: [ResolvedInputFile: URL]
    ) throws -> URL? {
        switch outputMode {
        case .stdout:
            return nil
        case .singleFile(let destination):
            return destination
        case .perFile:
            guard let destination = destinationMap[file] else {
                throw AppError.runtime("No output target was planned for this file.")
            }
            return destination
        }
    }
}
