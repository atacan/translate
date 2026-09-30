import Foundation

struct TranslationOrchestrator {
    func run(options: TranslateOptions, global: GlobalOptions) async throws {
        let terminal = TerminalIO(quiet: global.quiet, verbose: global.verbose)

        if global.verbose && global.quiet {
            throw AppError.invalidArguments("--verbose and --quiet cannot be used together.")
        }
        if options.stream && options.noStream {
            throw AppError.invalidArguments("--stream and --no-stream cannot be used together.")
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

        let inputMode = try await InputResolver().resolve(
            positional: options.input,
            forceText: options.text,
            terminal: terminal,
            cwd: cwd
        )

        let presetResolver = PresetResolver()
        let onlyCatalogs: Bool
        if case .files(let files, _) = inputMode { onlyCatalogs = files.allSatisfy(isCatalogFile(_:)) }
        else { onlyCatalogs = false }
        let activePresetName = presetResolver.activePresetName(cliPreset: options.preset, config: config, isCatalog: onlyCatalogs)
        let preset = try presetResolver.resolvePreset(named: activePresetName, config: config)

        if options.baseURL != nil, options.provider == nil {
            terminal.info("--base-url provided; provider set to openai-compatible.")
        }

        let fromRaw = options.from ?? preset.from ?? config.defaultsFrom
        let toRaw = options.to ?? preset.to ?? config.defaultsTo
        let from = try LanguageNormalizer.normalizeFrom(fromRaw)
        let to = try LanguageNormalizer.normalizeTo(toRaw)

        let formatHint = options.format ?? (FormatHint(rawValue: preset.format ?? "") ?? config.defaultsFormat)
        let jobs = max(1, options.jobs ?? config.defaultsJobs)
        let assumeYes = options.yes || config.defaultsYes
        let streamEnabled = options.noStream ? false : (options.stream ? true : config.defaultsStream)

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
        if options.stream && !outputPlan.mode.isStdout {
            terminal.warn("--stream has no effect unless output is stdout.")
        }

        let promptRenderer = PromptRenderer()
        let resolveExecutionContext = { (resolvedPreset: PresetDefinition, requireCredentials: Bool) throws -> (ProviderSelection, ResolvedPromptSet) in
            let providerSelection = try ProviderFactory(config: config, env: env).make(
                providerName: options.baseURL != nil && options.provider == nil
                    ? ProviderID.openAICompatible.rawValue
                    : options.provider ?? resolvedPreset.provider ?? config.defaultsProvider,
                modelOverride: options.model ?? resolvedPreset.model,
                baseURLOverride: options.baseURL,
                apiKeyOverride: options.apiKey,
                explicitProvider: options.provider != nil,
                requireCredentials: requireCredentials
            )

            let basePrompts: ResolvedPromptSet
            if providerSelection.promptless {
                basePrompts = ResolvedPromptSet(systemPrompt: "", userPrompt: "", customPromptActive: false)
                let ignoredFlags = ignoredPromptFlags(options: options)
                for flag in ignoredFlags {
                    if flag == "preset" {
                        terminal.warn("The prompt portion of --preset is ignored when using \(providerSelection.name); preset provider/model/language settings still apply.")
                    } else {
                        terminal.warn("--\(flag) is ignored when using \(providerSelection.name). This provider does not support custom prompts.")
                    }
                }
                if let userPreset = config.presets[resolvedPreset.name],
                   userPreset.systemPrompt != nil || userPreset.userPrompt != nil || userPreset.systemPromptFile != nil || userPreset.userPromptFile != nil {
                    terminal.warn("Prompt templates in config preset '\(resolvedPreset.name)' are ignored when using \(providerSelection.name); preset metadata still applies.")
                }
            } else {
                let resolved = try promptRenderer.resolvePrompts(
                    preset: resolvedPreset,
                    systemPromptOverride: options.systemPrompt,
                    userPromptOverride: options.userPrompt,
                    cwd: cwd,
                    noLang: options.noLang
                )
                basePrompts = resolved.0
                for warning in resolved.1 {
                    terminal.warn(warning.replacingOccurrences(of: "Warning: ", with: ""))
                }
            }

            return (providerSelection, basePrompts)
        }

        switch inputMode {
        case .inlineText(let inlineText):
            let (providerSelection, basePrompts) = try resolveExecutionContext(preset, !options.dryRun)
            let format = FormatDetector.detect(formatHint: formatHint, inputFile: nil)
            let renderedPrompts = promptRenderer.render(
                basePrompts,
                with: PromptRenderContext(
                    text: inlineText,
                    from: from,
                    to: to,
                    context: options.context ?? "",
                    filename: "",
                    format: format
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
                network: config.network,
                terminal: terminal,
                streamToStdout: streamEnabled && outputPlan.mode.isStdout
            )

            let writer = OutputWriter(terminal: terminal, prompter: ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes))
            let destination: URL?
            if translated.streamedToStdout {
                destination = nil
            } else {
                destination = try writer.write(translated.text, mode: outputPlan.mode)
            }
            if translated.strippedFence, global.verbose {
                terminal.info("Stripped wrapping code fence from LLM response.")
            }
            if global.verbose {
                emitVerboseMetadata(
                    terminal: terminal,
                    sourceLanguage: from,
                    providerName: providerSelection.name,
                    model: providerSelection.model,
                    usage: translated.usage,
                    elapsedMilliseconds: translated.elapsedMilliseconds,
                    destination: destination
                )
            }

        case .stdin(let stdinText):
            let (providerSelection, basePrompts) = try resolveExecutionContext(preset, !options.dryRun)
            let format = FormatDetector.detect(formatHint: formatHint, inputFile: nil)
            let renderedPrompts = promptRenderer.render(
                basePrompts,
                with: PromptRenderContext(
                    text: stdinText,
                    from: from,
                    to: to,
                    context: options.context ?? "",
                    filename: "",
                    format: format
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
                network: config.network,
                terminal: terminal,
                streamToStdout: streamEnabled && outputPlan.mode.isStdout
            )

            let writer = OutputWriter(terminal: terminal, prompter: ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes))
            let destination: URL?
            if translated.streamedToStdout {
                destination = nil
            } else {
                destination = try writer.write(translated.text, mode: outputPlan.mode)
            }
            if translated.strippedFence, global.verbose {
                terminal.info("Stripped wrapping code fence from LLM response.")
            }
            if global.verbose {
                emitVerboseMetadata(
                    terminal: terminal,
                    sourceLanguage: from,
                    providerName: providerSelection.name,
                    model: providerSelection.model,
                    usage: translated.usage,
                    elapsedMilliseconds: translated.elapsedMilliseconds,
                    destination: destination
                )
            }

        case .files(let files, _):
            let catalogFiles = files.filter(isCatalogFile(_:))
            let textFiles = files.filter { !isCatalogFile($0) }

            let inspections = textFiles.map(FileInspector.inspect)
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

            if validInspections.isEmpty && catalogFiles.isEmpty {
                if !immediateErrors.isEmpty { throw AppError.runtime("One or more files failed.") }
                return
            }

            let catalogPresetName = presetResolver.activePresetName(cliPreset: options.preset, config: config, isCatalog: true)
            // Resolve catalog metadata separately: a customized implicit xcode preset may carry its own
            // provider/model/languages. Never apply the text preset's metadata to that route.
            let catalogPreset = catalogFiles.isEmpty ? preset : try presetResolver.resolvePreset(named: catalogPresetName, config: config)
            let executionPreset = validInspections.isEmpty ? catalogPreset : preset
            let (providerSelection, basePrompts) = try resolveExecutionContext(executionPreset, !options.dryRun)
            let catalogFrom = try LanguageNormalizer.normalizeFrom(options.from ?? catalogPreset.from ?? config.defaultsFrom)
            let catalogTo = try LanguageNormalizer.normalizeTo(options.to ?? catalogPreset.to ?? config.defaultsTo)
            let catalogFormatHint = options.format ?? (FormatHint(rawValue: catalogPreset.format ?? "") ?? config.defaultsFormat)
            let (catalogProvider, catalogTemplates) = catalogFiles.isEmpty || catalogPresetName == executionPreset.name
                ? (providerSelection, basePrompts)
                : try resolveExecutionContext(catalogPreset, !options.dryRun)
            let catalogOrigins = PromptOrigins.resolve(preset: catalogPreset, config: config, options: options)
            let textOrigins = PromptOrigins.resolve(preset: preset, config: config, options: options)
            var catalogPlans: [ResolvedInputFile: CatalogPendingPlan] = [:]
            var catalogErrors: [TranslationFileResult] = []
            for file in catalogFiles {
                do {
                    let plan = try await CatalogPendingPlan.prepare(file: file, targetLanguage: catalogTo, jobs: jobs)
                    catalogPlans[file] = plan
                    plan.sourceWarnings(configuredSource: catalogFrom, filename: file.path.lastPathComponent).forEach(terminal.warn)
                    if catalogFormatHint != .auto && !catalogProvider.promptless {
                        terminal.warn("\(file.path.lastPathComponent): format '\(catalogFormatHint.rawValue)' affects segment {format} only; .xcstrings files always use catalog translation.")
                    }
                } catch {
                    let message = (error as? AppError)?.message ?? "\(file.path.path): \(error.localizedDescription)"
                    terminal.error(message)
                    catalogErrors.append(TranslationFileResult(file: file, destination: nil, success: false, errorMessage: message))
                }
            }
            func catalogPrompts(for file: ResolvedInputFile) -> CatalogPromptConfiguration {
                CatalogPromptConfiguration(
                    templates: catalogTemplates, context: options.context ?? "",
                    filename: file.path.lastPathComponent,
                    format: FormatDetector.detect(formatHint: catalogFormatHint, inputFile: file.path)
                )
            }

            var destinationMap: [ResolvedInputFile: URL] = {
                switch outputPlan.mode {
                case .stdout:
                    return [:]
                case .singleFile(let file):
                    guard let only = files.first else { return [:] }
                    return [only: file]
                case .perFile(let targets, _):
                    return Dictionary(uniqueKeysWithValues: targets.map { ($0.source, $0.destination) })
                }
            }()

            if case .perFile(_, let inPlace) = outputPlan.mode, !inPlace, options.suffix == nil,
               catalogTo.providerCode != to.providerCode {
                // Default suffixes follow the target of each input's preset.
                for file in catalogFiles {
                    let plan = try OutputPlanner().plan(OutputPlanningRequest(
                        inputMode: .files([file], cameFromGlob: true), toLanguage: catalogTo,
                        outputPath: nil, inPlace: false, suffix: nil, cwd: cwd
                    ))
                    if case .perFile(let targets, _) = plan.mode { destinationMap[file] = targets.first?.destination }
                }
            }

            if options.dryRun {
                for inspection in validInspections {
                    guard let text = inspection.content else { continue }
                    let renderedPrompts = promptRenderer.render(basePrompts, with: PromptRenderContext(
                        text: text, from: from, to: to, context: options.context ?? "",
                        filename: inspection.file.path.lastPathComponent,
                        format: FormatDetector.detect(formatHint: formatHint, inputFile: inspection.file.path)
                    ))
                    terminal.writeStdout("File: \(inspection.file.path.path)\nMode: text translation\nPreset: \(activePresetName)\nSystem prompt origin: \(providerSelection.promptless ? "unused (promptless provider)" : textOrigins.system)\nUser prompt origin: \(providerSelection.promptless ? "unused (promptless provider)" : textOrigins.user)")
                    terminal.writeStdout(DryRunPrinter.render(
                        provider: providerSelection.name, model: providerSelection.model, from: from,
                        to: to, prompts: renderedPrompts, inputText: text
                    ))
                }
                for file in catalogFiles {
                    guard let plan = catalogPlans[file] else { continue }
                    terminal.writeStdout(CatalogWorkflow().dryRunDescription(
                        file: file, plan: plan, providerName: catalogProvider.name, model: catalogProvider.model,
                        presetName: catalogPresetName,
                        presetOrigin: PromptOrigins.presetSelection(cliPreset: options.preset, config: config, isCatalog: true),
                        targetOrigin: options.to != nil ? "CLI --to" : (catalogPreset.to != nil ? "preset \(catalogPresetName).to" : "config/built-in defaults.to"),
                        origins: catalogOrigins, prompts: catalogPrompts(for: file),
                        promptless: catalogProvider.promptless, jobs: jobs, network: config.network
                    ))
                }
                if !catalogErrors.isEmpty || !immediateErrors.isEmpty { throw AppError.runtime("One or more files failed.") }
                return
            }

            if case .perFile(let targets, let inPlace) = outputPlan.mode, inPlace {
                let prompter = ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes)
                try prompter.confirm("This will overwrite \(targets.count) file(s). Proceed? [y/N]")
            }

            let writer = OutputWriter(
                terminal: terminal,
                prompter: ConfirmationPrompter(terminal: terminal, assumeYes: assumeYes),
                skipOverwriteConfirmation: outputPlan.mode.isInPlacePerFile
            )
            var results = immediateErrors + catalogErrors

            if !catalogFiles.isEmpty {
                let catalogWorkflow = CatalogWorkflow()
                for file in catalogFiles {
                    guard let plan = catalogPlans[file] else { continue }
                    let result = await catalogWorkflow.translateCatalogFile(
                        file: file,
                        targetLanguage: catalogTo,
                        prompts: catalogPrompts(for: file),
                        plan: plan,
                        provider: catalogProvider.provider,
                        jobs: jobs,
                        outputMode: outputPlan.mode,
                        destinationMap: destinationMap,
                        writer: writer,
                        terminal: terminal,
                        network: config.network
                    )
                    results.append(result)
                }
            }

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
                    providerName: providerSelection.name,
                    model: providerSelection.model,
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
                        providerName: providerSelection.name,
                        model: providerSelection.model,
                        verbose: global.verbose,
                        terminal: terminal,
                        network: config.network,
                        shouldStreamToStdout: streamEnabled
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

    private func isCatalogFile(_ file: ResolvedInputFile) -> Bool {
        file.path.pathExtension.lowercased() == "xcstrings"
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
        providerName: String,
        model: String?,
        verbose: Bool,
        terminal: TerminalIO,
        network: NetworkRuntimeConfig,
        shouldStreamToStdout: Bool
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
                network: network,
                terminal: terminal,
                streamToStdout: shouldStreamToStdout && outputMode.isStdout
            )
            if result.strippedFence, verbose {
                terminal.info("Stripped wrapping code fence from LLM response.")
            }

            let destination: URL?
            switch outputMode {
            case .stdout:
                if !result.streamedToStdout {
                    terminal.writeStdout(result.text)
                }
                destination = nil
            case .singleFile(let file):
                try writer.writeFile(text: result.text, destination: file)
                destination = file
            case .perFile:
                guard let destination = destinationMap[inspection.file] else {
                    return TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: "No output target was planned for this file.")
                }
                try writer.writeFile(text: result.text, destination: destination)
                if verbose {
                    emitVerboseMetadata(
                        terminal: terminal,
                        sourceLanguage: from,
                        providerName: providerName,
                        model: model,
                        usage: result.usage,
                        elapsedMilliseconds: result.elapsedMilliseconds,
                        destination: destination
                    )
                }
                return TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil)
            }

            if verbose {
                emitVerboseMetadata(
                    terminal: terminal,
                    sourceLanguage: from,
                    providerName: providerName,
                    model: model,
                    usage: result.usage,
                    elapsedMilliseconds: result.elapsedMilliseconds,
                    destination: destination
                )
            }
            return TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil)
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
        network: NetworkRuntimeConfig,
        terminal: TerminalIO,
        streamToStdout: Bool
    ) async throws -> TranslationExecutionResult {
        let providerRequest = ProviderRequest(
            from: from,
            to: to,
            systemPrompt: prompts.systemPrompt,
            userPrompt: prompts.userPrompt,
            text: sourceText,
            timeoutSeconds: network.timeoutSeconds,
            network: network
        )

        if streamToStdout, let stream = provider.streamTranslate(providerRequest) {
            let startedAt = Date()
            var aggregated = ""
            for try await chunk in stream {
                terminal.writeStdout(chunk, terminator: "")
                aggregated += chunk
            }
            if aggregated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProviderError.invalidResponse("Provider returned an empty response.")
            }
            if !aggregated.hasSuffix("\n") {
                terminal.writeStdout("", terminator: "\n")
            }
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            return TranslationExecutionResult(
                text: aggregated,
                strippedFence: false,
                usage: nil,
                elapsedMilliseconds: elapsed,
                streamedToStdout: true
            )
        }

        let startedAt = Date()
        let response = try await provider.translate(providerRequest)
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        let sanitized = ResponseSanitizer.stripWrappingCodeFence(response.text)
        return TranslationExecutionResult(
            text: sanitized.text,
            strippedFence: sanitized.stripped,
            usage: response.usage,
            elapsedMilliseconds: elapsed,
            streamedToStdout: false
        )
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
        providerName: String,
        model: String?,
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
            case success(text: String, strippedFence: Bool, usage: UsageInfo?, elapsedMilliseconds: Int)
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
                            let startedAt = Date()
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
                            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                            let sanitized = ResponseSanitizer.stripWrappingCodeFence(response.text)
                            output = .success(
                                text: sanitized.text,
                                strippedFence: sanitized.stripped,
                                usage: response.usage,
                                elapsedMilliseconds: elapsed
                            )
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
                            let startedAt = Date()
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
                            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                            let sanitized = ResponseSanitizer.stripWrappingCodeFence(response.text)
                            output = .success(
                                text: sanitized.text,
                                strippedFence: sanitized.stripped,
                                usage: response.usage,
                                elapsedMilliseconds: elapsed
                            )
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
            case .success(let text, let strippedFence, let usage, let elapsedMilliseconds):
                if strippedFence, verbose {
                    terminal.info("Stripped wrapping code fence from LLM response.")
                }
                do {
                    let destination: URL?
                    switch outputMode {
                    case .stdout:
                        terminal.writeStdout(text)
                        destination = nil
                    case .singleFile(let destination):
                        try writer.writeFile(text: text, destination: destination)
                        if verbose {
                            emitVerboseMetadata(
                                terminal: terminal,
                                sourceLanguage: from,
                                providerName: providerName,
                                model: model,
                                usage: usage,
                                elapsedMilliseconds: elapsedMilliseconds,
                                destination: destination
                            )
                        }
                        results.append(TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil))
                        continue
                    case .perFile:
                        guard let destination = destinationMap[inspection.file] else {
                            results.append(TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: "No output target was planned for this file."))
                            continue
                        }
                        try writer.writeFile(text: text, destination: destination)
                        if verbose {
                            emitVerboseMetadata(
                                terminal: terminal,
                                sourceLanguage: from,
                                providerName: providerName,
                                model: model,
                                usage: usage,
                                elapsedMilliseconds: elapsedMilliseconds,
                                destination: destination
                            )
                        }
                        results.append(TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil))
                        continue
                    }
                    if verbose {
                        emitVerboseMetadata(
                            terminal: terminal,
                            sourceLanguage: from,
                            providerName: providerName,
                            model: model,
                            usage: usage,
                            elapsedMilliseconds: elapsedMilliseconds,
                            destination: destination
                        )
                    }
                    results.append(TranslationFileResult(file: inspection.file, destination: destination, success: true, errorMessage: nil))
                } catch {
                    results.append(TranslationFileResult(file: inspection.file, destination: nil, success: false, errorMessage: error.localizedDescription))
                }
            }
        }

        return results
    }

    private func emitVerboseMetadata(
        terminal: TerminalIO,
        sourceLanguage: NormalizedLanguage,
        providerName: String,
        model: String?,
        usage: UsageInfo?,
        elapsedMilliseconds: Int,
        destination: URL?
    ) {
        terminal.info("Provider: \(providerName)")
        terminal.info("Model: \(model ?? "(provider default)")")
        if sourceLanguage.isAuto {
            terminal.info("Detected source language: unavailable (provider did not report)")
        } else {
            terminal.info("Detected source language: \(sourceLanguage.displayName)")
        }
        if let usage {
            let input = usage.inputTokens.map(String.init) ?? "n/a"
            let output = usage.outputTokens.map(String.init) ?? "n/a"
            terminal.info("Tokens: input=\(input), output=\(output)")
        } else {
            terminal.info("Tokens: unavailable")
        }
        terminal.info("Elapsed: \(elapsedMilliseconds)ms")
        terminal.info("Output: \(destination?.path ?? "stdout")")
    }
}

private struct TranslationExecutionResult {
    let text: String
    let strippedFence: Bool
    let usage: UsageInfo?
    let elapsedMilliseconds: Int
    let streamedToStdout: Bool
}

private extension OutputMode {
    var isStdout: Bool {
        if case .stdout = self {
            return true
        }
        return false
    }

    var isInPlacePerFile: Bool {
        if case .perFile(_, let inPlace) = self {
            return inPlace
        }
        return false
    }
}
