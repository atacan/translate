import Foundation

struct TranslationOrchestrator {
    func run(options: TranslateOptions, global: GlobalOptions) async throws {
        let terminal = TerminalIO(quiet: global.quiet, verbose: global.verbose)

        if global.verbose && global.quiet {
            throw AppError.invalidArguments("--verbose and --quiet cannot be used together.")
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        let configPath = ConfigLocator.resolvedConfigPath(cli: global.config, env: env, cwd: cwd, home: home)
        let configStore = ConfigStore()
        let configTable = try configStore.load(path: configPath)
        let config = ConfigResolver().resolve(path: configPath, table: configTable)

        for warning in ConfigResolver().namedProviderCollisionWarnings(config) {
            terminal.warn(warning.replacingOccurrences(of: "Warning: ", with: ""))
        }

        let presetResolver = PresetResolver()
        let activePresetName = presetResolver.activePresetName(cliPreset: options.preset, config: config)
        let preset = try presetResolver.resolvePreset(named: activePresetName, config: config)

        let providerName: String
        if options.baseURL != nil, options.provider == nil {
            providerName = ProviderID.openAICompatible.rawValue
            terminal.info("--base-url provided; provider set to openai-compatible.")
        } else {
            providerName = options.provider ?? preset.provider ?? config.defaultsProvider
        }

        let fromRaw = options.from ?? preset.from ?? config.defaultsFrom
        let toRaw = options.to ?? preset.to ?? config.defaultsTo
        let from = try LanguageNormalizer.normalizeFrom(fromRaw)
        let to = try LanguageNormalizer.normalizeTo(toRaw)

        let formatHint = options.format ?? (FormatHint(rawValue: preset.format ?? "") ?? config.defaultsFormat)
        let jobs = max(1, options.jobs ?? config.defaultsJobs)
        let assumeYes = options.yes || config.defaultsYes

        let inputMode = try await InputResolver().resolve(
            positional: options.input,
            forceText: options.text,
            terminal: terminal,
            cwd: cwd
        )

        if options.jobs != nil {
            switch inputMode {
            case .files:
                break
            case .inlineText, .stdin:
                terminal.warn("--jobs has no effect for non-file input.")
            }
        }

        let outputPlan = try OutputPlanner().plan(
            OutputPlanningRequest(
                inputMode: inputMode,
                toLanguage: to,
                outputPath: options.output,
                inPlace: options.inPlace,
                suffix: options.suffix,
                cwd: cwd
            )
        )
        outputPlan.warnings.forEach { terminal.warn($0.replacingOccurrences(of: "Warning: ", with: "")) }

        let providerSelection = try ProviderFactory(config: config, env: env).make(
            providerName: providerName,
            modelOverride: options.model ?? preset.model,
            baseURLOverride: options.baseURL,
            apiKeyOverride: options.apiKey,
            explicitProvider: options.provider != nil
        )

        var promptWarnings: [String] = []
        let promptRenderer = PromptRenderer()
        let basePrompts: ResolvedPromptSet

        if providerSelection.promptless {
            basePrompts = ResolvedPromptSet(systemPrompt: "", userPrompt: "", customPromptActive: false)
            let ignoredFlags = ignoredPromptFlags(options: options)
            for flag in ignoredFlags {
                terminal.warn("--\(flag) is ignored when using \(providerSelection.name). This provider does not support custom prompts.")
            }
        } else {
            let resolved = try promptRenderer.resolvePrompts(
                preset: preset,
                systemPromptOverride: options.systemPrompt,
                userPromptOverride: options.userPrompt,
                cwd: cwd,
                noLang: options.noLang
            )
            basePrompts = resolved.0
            promptWarnings = resolved.1
        }

        for warning in promptWarnings {
            terminal.warn(warning.replacingOccurrences(of: "Warning: ", with: ""))
        }

        switch inputMode {
        case .inlineText(let inlineText):
            let renderedPrompts = promptRenderer.render(
                basePrompts,
                with: PromptRenderContext(
                    text: inlineText,
                    from: from,
                    to: to,
                    context: options.context ?? "",
                    filename: "",
                    format: .text
                )
            )
            if options.dryRun {
                terminal.writeStdout(
                    DryRunPrinter.render(
                        provider: providerSelection.name,
                        model: providerSelection.model,
                        from: from,
                        to: to,
                        prompts: renderedPrompts,
                        inputText: inlineText
                    )
                )
                return
            }

            let translated = try await translateSingleText(
                sourceText: inlineText,
                provider: providerSelection.provider,
                prompts: renderedPrompts,
                from: from,
                to: to,
                network: config.network
            )

            let writer = OutputWriter(terminal: terminal, prompter: ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes))
            _ = try writer.write(translated.text, mode: outputPlan.mode)
            if translated.strippedFence, global.verbose {
                terminal.info("Stripped wrapping code fence from LLM response.")
            }

        case .stdin(let stdinText):
            let renderedPrompts = promptRenderer.render(
                basePrompts,
                with: PromptRenderContext(
                    text: stdinText,
                    from: from,
                    to: to,
                    context: options.context ?? "",
                    filename: "",
                    format: .text
                )
            )
            if options.dryRun {
                terminal.writeStdout(
                    DryRunPrinter.render(
                        provider: providerSelection.name,
                        model: providerSelection.model,
                        from: from,
                        to: to,
                        prompts: renderedPrompts,
                        inputText: stdinText
                    )
                )
                return
            }

            let translated = try await translateSingleText(
                sourceText: stdinText,
                provider: providerSelection.provider,
                prompts: renderedPrompts,
                from: from,
                to: to,
                network: config.network
            )

            let writer = OutputWriter(terminal: terminal, prompter: ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes))
            _ = try writer.write(translated.text, mode: outputPlan.mode)
            if translated.strippedFence, global.verbose {
                terminal.info("Stripped wrapping code fence from LLM response.")
            }

        case .files(let files, _):
            let inspections = files.map(FileInspector.inspect)
            for inspection in inspections where inspection.warning != nil {
                terminal.warn(inspection.warning!)
            }

            let validInspections = inspections.filter { $0.content != nil }
            let immediateErrors = inspections.compactMap { inspection -> TranslationFileResult? in
                if let error = inspection.error {
                    terminal.error("Error: \(error)")
                    return TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: error)
                }
                return nil
            }

            if validInspections.isEmpty {
                if !immediateErrors.isEmpty {
                    throw AppError.runtime("One or more files failed.")
                }
                throw AppError.runtime("Error: Input text is empty.")
            }

            let destinationMap: [ResolvedInputFile: URL] = {
                switch outputPlan.mode {
                case .stdout:
                    return [:]
                case .singleFile(let file):
                    guard let only = validInspections.first else { return [:] }
                    return [only.file: file]
                case .perFile(let targets, _):
                    return Dictionary(uniqueKeysWithValues: targets.map { ($0.source, $0.destination) })
                }
            }()

            if case .perFile(let targets, let inPlace) = outputPlan.mode, inPlace {
                let prompter = ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes)
                try prompter.confirm("This will overwrite \(targets.count) file(s). Proceed? [y/N]")
            }

            if options.dryRun {
                guard let first = validInspections.first, let text = first.content else {
                    throw AppError.runtime("Error: Input text is empty.")
                }
                let format = FormatDetector.detect(formatHint: formatHint, inputFile: first.file.path)
                let renderedPrompts = promptRenderer.render(
                    basePrompts,
                    with: PromptRenderContext(
                        text: text,
                        from: from,
                        to: to,
                        context: options.context ?? "",
                        filename: first.file.path.lastPathComponent,
                        format: format
                    )
                )
                terminal.writeStdout(
                    DryRunPrinter.render(
                        provider: providerSelection.name,
                        model: providerSelection.model,
                        from: from,
                        to: to,
                        prompts: renderedPrompts,
                        inputText: text
                    )
                )
                return
            }

            let writer = OutputWriter(terminal: terminal, prompter: ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes))
            var results = immediateErrors

            if jobs > 1 && validInspections.count > 1 {
                let concurrentResults = try await translateFilesConcurrently(
                    inspections: validInspections,
                    jobs: jobs,
                    formatHint: formatHint,
                    promptRenderer: promptRenderer,
                    basePrompts: basePrompts,
                    provider: providerSelection.provider,
                    from: from,
                    to: to,
                    context: options.context ?? "",
                    outputMode: outputPlan.mode,
                    destinationMap: destinationMap,
                    writer: writer,
                    verbose: global.verbose,
                    terminal: terminal,
                    network: config.network
                )
                results.append(contentsOf: concurrentResults)
            } else {
                for inspection in validInspections {
                    results.append(try await translateFile(
                        inspection: inspection,
                        formatHint: formatHint,
                        promptRenderer: promptRenderer,
                        basePrompts: basePrompts,
                        provider: providerSelection.provider,
                        from: from,
                        to: to,
                        context: options.context ?? "",
                        outputMode: outputPlan.mode,
                        destinationMap: destinationMap,
                        writer: writer,
                        verbose: global.verbose,
                        terminal: terminal,
                        network: config.network
                    ))
                }
            }

            let failures = results.filter { !$0.success }
            let successes = results.filter { $0.success }

            if !failures.isEmpty {
                terminal.writeStderr("Translation complete: \(successes.count) succeeded, \(failures.count) failed.")
                terminal.writeStderr("Failed files:")
                for failed in failures {
                    terminal.writeStderr("  - \(failed.file.path.lastPathComponent): \(failed.errorMessage ?? "unknown error")")
                }
                throw AppError.runtime("One or more files failed.")
            }
        }
    }

    private func translateFile(
        inspection: FileInspection,
        formatHint: FormatHint,
        promptRenderer: PromptRenderer,
        basePrompts: ResolvedPromptSet,
        provider: any TranslationProvider,
        from: NormalizedLanguage,
        to: NormalizedLanguage,
        context: String,
        outputMode: OutputMode,
        destinationMap: [ResolvedInputFile: URL],
        writer: OutputWriter,
        verbose: Bool,
        terminal: TerminalIO,
        network: NetworkRuntimeConfig
    ) async throws -> TranslationFileResult {
        guard let text = inspection.content else {
            return TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: inspection.error)
        }

        let format = FormatDetector.detect(formatHint: formatHint, inputFile: inspection.file.path)
        let renderedPrompts = promptRenderer.render(
            basePrompts,
            with: PromptRenderContext(
                text: text,
                from: from,
                to: to,
                context: context,
                filename: inspection.file.path.lastPathComponent,
                format: format
            )
        )

        do {
            let result = try await translateSingleText(
                sourceText: text,
                provider: provider,
                prompts: renderedPrompts,
                from: from,
                to: to,
                network: network
            )
            if result.strippedFence, verbose {
                terminal.info("Stripped wrapping code fence from LLM response.")
            }

            switch outputMode {
            case .stdout:
                terminal.writeStdout(result.text)
                return TranslationFileResult(file: inspection.file, destination: nil, success: true, errorMessage: nil)
            case .singleFile(let file):
                try writer.writeFile(text: result.text, destination: file)
                return TranslationFileResult(file: inspection.file, destination: file, success: true, errorMessage: nil)
            case .perFile:
                guard let destination = destinationMap[inspection.file] else {
                    return TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: "No output target was planned for this file.")
                }
                try writer.writeFile(text: result.text, destination: destination)
                return TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil)
            }
        } catch let providerError as ProviderError {
            return TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: providerError.message)
        } catch {
            return TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: error.localizedDescription)
        }
    }

    private func ignoredPromptFlags(options: TranslateOptions) -> [String] {
        var flags: [String] = []
        if options.systemPrompt != nil { flags.append("system-prompt") }
        if options.userPrompt != nil { flags.append("user-prompt") }
        if options.context != nil { flags.append("context") }
        if options.preset != nil { flags.append("preset") }
        if options.format != nil { flags.append("format") }
        return flags
    }

    private func translateSingleText(
        sourceText: String,
        provider: any TranslationProvider,
        prompts: ResolvedPromptSet,
        from: NormalizedLanguage,
        to: NormalizedLanguage,
        network: NetworkRuntimeConfig
    ) async throws -> (text: String, strippedFence: Bool) {
        let response = try await provider.translate(
            ProviderRequest(
                from: from,
                to: to,
                systemPrompt: prompts.systemPrompt,
                userPrompt: prompts.userPrompt,
                text: sourceText,
                timeoutSeconds: network.timeoutSeconds,
                network: network
            )
        )

        let sanitized = ResponseSanitizer.stripWrappingCodeFence(response.text)
        return (text: sanitized.text, strippedFence: sanitized.stripped)
    }

    private func translateFilesConcurrently(
        inspections: [FileInspection],
        jobs: Int,
        formatHint: FormatHint,
        promptRenderer: PromptRenderer,
        basePrompts: ResolvedPromptSet,
        provider: any TranslationProvider,
        from: NormalizedLanguage,
        to: NormalizedLanguage,
        context: String,
        outputMode: OutputMode,
        destinationMap: [ResolvedInputFile: URL],
        writer: OutputWriter,
        verbose: Bool,
        terminal: TerminalIO,
        network: NetworkRuntimeConfig
    ) async throws -> [TranslationFileResult] {
        struct TaskInput: Sendable {
            let index: Int
            let file: ResolvedInputFile
            let text: String
            let prompts: ResolvedPromptSet
        }

        enum TaskOutput: Sendable {
            case success(text: String, strippedFence: Bool)
            case failure(String)
        }

        let taskInputs: [TaskInput] = inspections.enumerated().compactMap { index, inspection in
            guard let text = inspection.content else { return nil }
            let format = FormatDetector.detect(formatHint: formatHint, inputFile: inspection.file.path)
            let prompts = promptRenderer.render(
                basePrompts,
                with: PromptRenderContext(
                    text: text,
                    from: from,
                    to: to,
                    context: context,
                    filename: inspection.file.path.lastPathComponent,
                    format: format
                )
            )
            return TaskInput(index: index, file: inspection.file, text: text, prompts: prompts)
        }

        var taskOutputs: [Int: TaskOutput] = [:]
        try await withThrowingTaskGroup(of: (Int, TaskOutput).self) { group in
            var iterator = taskInputs.makeIterator()
            let initial = min(max(1, jobs), taskInputs.count)
            for _ in 0..<initial {
                if let next = iterator.next() {
                    group.addTask {
                        let output: TaskOutput
                        do {
                            let response = try await provider.translate(
                                ProviderRequest(
                                    from: from,
                                    to: to,
                                    systemPrompt: next.prompts.systemPrompt,
                                    userPrompt: next.prompts.userPrompt,
                                    text: next.text,
                                    timeoutSeconds: network.timeoutSeconds,
                                    network: network
                                )
                            )
                            let sanitized = ResponseSanitizer.stripWrappingCodeFence(response.text)
                            output = .success(text: sanitized.text, strippedFence: sanitized.stripped)
                        } catch let providerError as ProviderError {
                            output = .failure(providerError.message)
                        } catch {
                            output = .failure(error.localizedDescription)
                        }
                        return (next.index, output)
                    }
                }
            }

            while let (index, output) = try await group.next() {
                taskOutputs[index] = output
                if let next = iterator.next() {
                    group.addTask {
                        let output: TaskOutput
                        do {
                            let response = try await provider.translate(
                                ProviderRequest(
                                    from: from,
                                    to: to,
                                    systemPrompt: next.prompts.systemPrompt,
                                    userPrompt: next.prompts.userPrompt,
                                    text: next.text,
                                    timeoutSeconds: network.timeoutSeconds,
                                    network: network
                                )
                            )
                            let sanitized = ResponseSanitizer.stripWrappingCodeFence(response.text)
                            output = .success(text: sanitized.text, strippedFence: sanitized.stripped)
                        } catch let providerError as ProviderError {
                            output = .failure(providerError.message)
                        } catch {
                            output = .failure(error.localizedDescription)
                        }
                        return (next.index, output)
                    }
                }
            }
        }

        var results: [TranslationFileResult] = []
        for (index, inspection) in inspections.enumerated() {
            guard let output = taskOutputs[index] else {
                results.append(TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: "Translation task did not produce a result."))
                continue
            }

            switch output {
            case .failure(let errorMessage):
                results.append(TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: errorMessage))
            case .success(let text, let strippedFence):
                if strippedFence, verbose {
                    terminal.info("Stripped wrapping code fence from LLM response.")
                }
                do {
                    switch outputMode {
                    case .stdout:
                        terminal.writeStdout(text)
                        results.append(TranslationFileResult(file: inspection.file, destination: nil, success: true, errorMessage: nil))
                    case .singleFile(let destination):
                        try writer.writeFile(text: text, destination: destination)
                        results.append(TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil))
                    case .perFile:
                        guard let destination = destinationMap[inspection.file] else {
                            results.append(TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: "No output target was planned for this file."))
                            continue
                        }
                        try writer.writeFile(text: text, destination: destination)
                        results.append(TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil))
                    }
                } catch {
                    results.append(TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: error.localizedDescription))
                }
            }
        }

        return results
    }
}
