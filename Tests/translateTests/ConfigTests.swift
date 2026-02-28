import XCTest
import TOMLKit
@testable import translate

final class ConfigTests: XCTestCase {
    func testNetworkConfigValuesAreClamped() {
        let table = TOMLTable()
        ConfigKeyPath.set(table: table, key: "network.timeout_seconds", value: 0)
        ConfigKeyPath.set(table: table, key: "network.retries", value: -4)
        ConfigKeyPath.set(table: table, key: "network.retry_base_delay_seconds", value: 0)

        let resolved = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table)
        XCTAssertEqual(resolved.network.timeoutSeconds, 1)
        XCTAssertEqual(resolved.network.retries, 0)
        XCTAssertEqual(resolved.network.retryBaseDelaySeconds, 1)
    }

    func testNamedProviderCollisionWarningsAreGenerated() {
        let table = TOMLTable()
        ConfigKeyPath.set(table: table, key: "providers.openai-compatible.openai.base_url", value: "http://localhost:1234/v1")
        ConfigKeyPath.set(table: table, key: "providers.openai-compatible.openai.model", value: "dummy")

        let resolved = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table)
        let warnings = ConfigResolver().namedProviderCollisionWarnings(resolved)

        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("Named endpoint 'openai'"))
    }

    func testDefaultsStreamConfigIsResolvedAndIncludedInEffectiveConfig() {
        let table = TOMLTable()
        ConfigKeyPath.set(table: table, key: "defaults.stream", value: true)

        let resolved = ConfigResolver().resolve(path: URL(fileURLWithPath: "/tmp/config.toml"), table: table)
        XCTAssertTrue(resolved.defaultsStream)

        let effectiveDefaults = ConfigResolver().effectiveConfigTable(resolved)["defaults"]?.table
        XCTAssertEqual(effectiveDefaults?["stream"]?.bool, true)
    }

    func testConfigLocatorPrefersCLIOverEnvironment() {
        let resolved = ConfigLocator.resolvedConfigPath(
            cli: "/tmp/from-cli.toml",
            env: ["TRANSLATE_CONFIG": "/tmp/from-env.toml"],
            cwd: URL(fileURLWithPath: "/tmp/cwd"),
            home: URL(fileURLWithPath: "/Users/test")
        )
        XCTAssertEqual(resolved.path, "/tmp/from-cli.toml")
    }
}
