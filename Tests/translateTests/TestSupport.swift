import XCTest
import Foundation
@testable import translate

struct MockTranslationProvider: TranslationProvider {
    let id: ProviderID = .openai
    let translateImpl: @Sendable (ProviderRequest) async throws -> ProviderResult

    func translate(_ request: ProviderRequest) async throws -> ProviderResult {
        try await translateImpl(request)
    }
}

enum TestSupport {
    static func makeTemporaryDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("translate-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
