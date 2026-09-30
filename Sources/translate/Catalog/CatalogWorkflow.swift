import Foundation
import CatalogTranslation
import StringCatalog

struct CatalogWorkflow {
    func translateCatalogFile(
        file: ResolvedInputFile,
        targetLanguage: NormalizedLanguage,
        prompts: CatalogPromptConfiguration? = nil,
        plan: CatalogPendingPlan? = nil,
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
            else { pendingPlan = try await CatalogPendingPlan.prepare(file: file, targetLanguage: targetLanguage, jobs: jobs) }
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
            let translation = try await pendingPlan.translate(using: translator, jobs: jobs)
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
