import Foundation
import TOMLKit
import XCTest
@testable import translate

final class ConfigLoadingTests: XCTestCase {
    func testMissingImplicitDefaultUsesBuiltInsButExplicitSelectionsFail() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = ConfigLocator.resolvedConfigPath(cli: nil, env: [:], cwd: directory, home: directory)
        XCTAssertFalse(ConfigLocator.isExplicitlySelected(cli: nil, env: [:]))
        let table = try ConfigStore().load(path: path)
        XCTAssertEqual(ConfigResolver().resolve(path: path, table: table).defaultsPreset, "general")
        for selection in [(nil as String?, ["TRANSLATE_CONFIG": path.path]), (path.path as String?, [:])] {
            XCTAssertThrowsError(try ConfigStore().load(path: path, requireExists: ConfigLocator.isExplicitlySelected(cli: selection.0, env: selection.1)))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testSchemaWarningsIdentifyWrongKeysAndTypesWithoutValues() throws {
        let table = try TOMLTable(string: """
        system_prompt = "secret-top-level"
        [defaults]
        prompt = "secret-default"
        preset = 4
        stream = "secret-stream"
        jobs = false
        format = "secret-format"
        [presets.general]
        system_promt = "secret-typo"
        user_prompt_file = ["secret-file"]
        model = true
        description = "supported description"
        [presets.bad]
        format = "secret-preset-format"
        """)
        let config = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table)
        let warnings = ConfigResolver().warnings(config).joined(separator: "\n")
        for key in ["system_prompt", "defaults.prompt", "defaults.preset", "defaults.stream", "defaults.jobs", "defaults.format", "presets.general.system_promt", "presets.general.user_prompt_file", "presets.general.model", "presets.bad.format"] {
            XCTAssertTrue(warnings.contains("'\(key)'"), warnings)
        }
        XCTAssertTrue(warnings.contains("must be a string"))
        XCTAssertTrue(warnings.contains("Supported keys:"))
        XCTAssertFalse(warnings.contains("secret-"))
        XCTAssertFalse(warnings.contains("presets.general.description"))
        XCTAssertEqual(config.presets["general"]?.description, "supported description")
    }

    func testWrongSectionShapesAndUnknownDefaultPresetAreDiagnosed() throws {
        for (text, key) in [("defaults = []", "defaults"), ("presets = 3", "presets"), ("[presets]\ngeneral = false", "presets.general"), ("[defaults]\npreset = 'secret-unknown'", "defaults.preset")] {
            let config = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: try TOMLTable(string: text))
            let warning = ConfigResolver().warnings(config).joined()
            XCTAssertTrue(warning.contains("'\(key)'"))
            XCTAssertFalse(warning.contains("secret-unknown"))
        }
    }

    func testPresetFilesResolveBesideConfigAndRawPathsStayIntact() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        let file = directory.appendingPathComponent("user.txt")
        try "Config file {text}".write(to: file, atomically: true, encoding: .utf8)
        let table = try TOMLTable(string: """
        [presets.files]
        user_prompt_file = "user.txt"
        system_prompt_file = "~/system.txt"
        [presets.absolute]
        user_prompt_file = "\(file.path)"
        """)
        let config = ConfigResolver().resolve(path: configPath, table: table)
        XCTAssertEqual(config.presets["files"]?.userPromptFile, file.path)
        XCTAssertEqual(config.presets["files"]?.systemPromptFile, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("system.txt").path)
        XCTAssertEqual(config.presets["absolute"]?.userPromptFile, file.path)
        XCTAssertEqual(config.table["presets"]?["files"]?["user_prompt_file"]?.string, "user.txt")
        XCTAssertEqual(ConfigResolver().effectiveConfigTable(config)["presets"]?["files"]?["user_prompt_file"]?.string, "user.txt")
        let preset = try PresetResolver().resolvePreset(named: "files", config: config)
        // CLI override skips the missing system file, while the user file works outside config cwd.
        let prompts = try PromptRenderer().resolvePrompts(preset: preset, systemPromptOverride: "CLI {to}", userPromptOverride: nil, cwd: URL(fileURLWithPath: "/"), noLang: false).0
        XCTAssertEqual(prompts.userPrompt, "Config file {text}")
    }

    func testCustomPresetFallsBackToOriginalGeneralAndShadowOriginsArePerField() throws {
        let table = try TOMLTable(string: """
        [presets.general]
        system_prompt = "Customized {to}"
        [presets.other]
        model = "metadata-only"
        [presets.legal]
        user_prompt = "Legal {text}"
        """)
        let config = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table)
        let resolver = PresetResolver()
        let custom = try resolver.resolvePreset(named: "other", config: config)
        XCTAssertEqual(custom.systemPrompt, BuiltInPresetStore.all()["general"]?.systemPrompt)
        let legal = try resolver.resolvePreset(named: "legal", config: config)
        XCTAssertEqual(legal.systemPrompt, BuiltInPresetStore.all()["legal"]?.systemPrompt)
        let origins = PromptOrigins.resolve(preset: legal, config: config)
        XCTAssertEqual(origins.system, "built-in preset legal")
        XCTAssertEqual(origins.user, "user preset legal inline")
        XCTAssertEqual(resolver.list(config: config).builtIn.first { $0.name == "legal" }?.source, .userDefined)
    }
}

final class ConfigLoadingCLITests: XCTestCase {
    func testExplicitMissingCLIAndEnvironmentFailAcrossReadOnlyCommands() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.toml").path
        let commands = [["--text", "--dry-run", "hello"], ["config", "show"], ["config", "get", "defaults.preset"], ["presets", "list"], ["presets", "show", "general"], ["presets", "which"]]
        for command in commands {
            for useEnvironment in [false, true] {
                let result = try run(directory, command + (useEnvironment ? [] : ["--config", missing]), env: useEnvironment ? ["TRANSLATE_CONFIG": missing] : [:])
                XCTAssertEqual(result.status, 1, result.stderr)
                XCTAssertTrue(result.stderr.contains("Config file '\(missing)' not found"), result.stderr)
                XCTAssertFalse(FileManager.default.fileExists(atPath: missing))
            }
        }
    }

    func testPathInspectionCreationAndUnsetAreSafeForNewExplicitPaths() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for useEnvironment in [false, true] {
            let path = directory.appendingPathComponent(useEnvironment ? "env/new.toml" : "cli/new.toml")
            let env = useEnvironment ? ["TRANSLATE_CONFIG": path.path] : [:]
            let selection = useEnvironment ? [] : ["--config", path.path]
            let inspection = try run(directory, ["config", "path"] + selection, env: env)
            XCTAssertEqual(inspection.status, 0)
            XCTAssertEqual(inspection.stdout.trimmingCharacters(in: .whitespacesAndNewlines), path.path)
            XCTAssertEqual(try run(directory, ["config", "unset", "defaults.preset"] + selection, env: env).status, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
            XCTAssertEqual(try run(directory, ["config", "edit"] + selection, env: env.merging(["EDITOR": "/usr/bin/true"]) { _, new in new }).status, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
            try FileManager.default.removeItem(at: path)
            XCTAssertEqual(try run(directory, ["config", "set", "defaults.preset", "legal"] + selection, env: env).status, 0)
            XCTAssertEqual(try ConfigStore().load(path: path)["defaults"]?["preset"]?.string, "legal")
        }
    }

    func testCLISelectionLoadsOneConfigAndRelativePromptFilesUseDistinctDirectories() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configDirectory = directory.appendingPathComponent("settings")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let config = configDirectory.appendingPathComponent("config.toml")
        try """
        [defaults]
        provider = "ollama"
        preset = "general"
        [presets.general]
        system_prompt = "Configured {to}"
        system_prompt_file = "missing-overridden.txt"
        user_prompt_file = "user.txt"
        [presets.inactive]
        user_prompt_file = "missing-inactive.txt"
        """.write(to: config, atomically: true, encoding: .utf8)
        try "Beside config {text}".write(to: configDirectory.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)
        try "Invocation cwd {to}".write(to: directory.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
        try "Wrong cwd {text}".write(to: directory.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)
        let result = try run(directory, ["--config", "settings/config.toml", "--text", "--dry-run", "--system-prompt", "@system.txt", "hello"], env: ["TRANSLATE_CONFIG": directory.appendingPathComponent("missing-env.toml").path])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Invocation cwd English"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Beside config hello"), result.stdout)
        XCTAssertFalse(result.stdout.contains("Wrong cwd"))
        XCTAssertTrue(result.stdout.contains("System prompt origin: CLI file system.txt"))
        XCTAssertTrue(result.stdout.contains("User prompt origin: user preset general file \(configDirectory.appendingPathComponent("user.txt").path)"))
        let list = try run(directory, ["presets", "list", "--config", config.path])
        XCTAssertEqual(list.status, 0, list.stderr)
        XCTAssertTrue(list.stdout.contains("[overridden in config]"))
        let show = try run(directory, ["presets", "show", "general", "--config", config.path])
        XCTAssertEqual(show.status, 0, show.stderr)
        XCTAssertTrue(show.stdout.contains("System prompt origin: user preset general inline"))
        XCTAssertTrue(show.stdout.contains("Beside config {text}"))
        let which = try run(directory, ["presets", "which", "--config", config.path])
        XCTAssertEqual(which.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "general (user-defined)")
    }

    func testConfigDiagnosticsReachTranslationAndInspectionWithoutSecrets() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config.toml")
        try """
        [defaults]
        provider = "ollama"
        stream = "secret-wrong-type"
        [presets.general]
        system_promt = "secret-wrong-key"
        user_prompt = 5
        """.write(to: config, atomically: true, encoding: .utf8)
        for command in [["--text", "--dry-run", "hello"], ["config", "show"], ["config", "get", "defaults.provider"], ["presets", "list"], ["presets", "show", "general"], ["presets", "which"]] {
            let result = try run(directory, command + ["--config", config.path])
            XCTAssertEqual(result.status, 0, result.stderr)
            for key in ["defaults.stream", "presets.general.system_promt", "presets.general.user_prompt"] {
                XCTAssertTrue(result.stderr.contains("'\(key)'"), result.stderr)
            }
            XCTAssertFalse(result.stderr.contains("secret-"))
        }
    }

    private func run(_ directory: URL, _ arguments: [String], env: [String: String] = [:]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("translate")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // Never inherit the user's config selector, credentials, or editor.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": directory.path].merging(env) { _, new in new }
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
