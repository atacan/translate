import Foundation

struct RetryPolicy {
    typealias Sleeper = @Sendable (Double) async throws -> Void
    typealias NowProvider = @Sendable () -> Date
    typealias Randomizer = @Sendable (ClosedRange<Double>) -> Double

    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    let maxAttempts: Int
    private let baseDelaySeconds: Int
    private let sleeper: Sleeper
    private let now: NowProvider
    private let randomizer: Randomizer

    init(
        network: NetworkRuntimeConfig,
        sleeper: @escaping Sleeper,
        now: @escaping NowProvider = { Date() },
        randomizer: @escaping Randomizer = { range in Double.random(in: range) }
    ) {
        self.init(
            maxAttempts: max(1, network.retries + 1),
            baseDelaySeconds: network.retryBaseDelaySeconds,
            sleeper: sleeper,
            now: now,
            randomizer: randomizer
        )
    }

    init(
        maxAttempts: Int,
        baseDelaySeconds: Int,
        sleeper: @escaping Sleeper,
        now: @escaping NowProvider = { Date() },
        randomizer: @escaping Randomizer = { range in Double.random(in: range) }
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelaySeconds = max(1, baseDelaySeconds)
        self.sleeper = sleeper
        self.now = now
        self.randomizer = randomizer
    }

    func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        attempt < maxAttempts && Self.shouldRetry(statusCode: statusCode)
    }

    static func shouldRetry(statusCode: Int) -> Bool {
        retryableStatusCodes.contains(statusCode)
    }

    func delaySeconds(attempt: Int, headers: [String: String]) -> Double {
        if let retryAfterHeader = headers.first(where: { $0.key.caseInsensitiveCompare("retry-after") == .orderedSame })?.value,
           let retryAfter = parseRetryAfter(retryAfterHeader)
        {
            return retryAfter
        }

        let exponential = min(Double(baseDelaySeconds) * pow(2.0, Double(max(1, attempt) - 1)), 30.0)
        let jitter = exponential * 0.2
        return max(0, exponential + randomizer(-jitter...jitter))
    }

    func sleepBeforeRetry(attempt: Int, headers: [String: String]) async throws {
        let delay = delaySeconds(attempt: attempt, headers: headers)
        try await sleeper(delay)
    }

    private func parseRetryAfter(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(trimmed), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        guard let date = formatter.date(from: trimmed) else {
            return nil
        }

        return max(0, date.timeIntervalSince(now()))
    }
}
