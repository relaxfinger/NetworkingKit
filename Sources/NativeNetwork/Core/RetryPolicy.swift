import Foundation

/// 针对临时故障的指数退避策略。默认不重试，避免在非幂等请求上产生意外副作用。
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let multiplier: Double

    public init(maxAttempts: Int = 1, initialDelay: TimeInterval = 0.25, multiplier: Double = 2) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelay = max(0, initialDelay)
        self.multiplier = max(1, multiplier)
    }

    public static let none = RetryPolicy()

    func shouldRetry(_ error: NetworkError) -> Bool {
        switch error {
        case let .http(statusCode, _, _): return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .transport: return true
        default: return false
        }
    }

    func delayNanoseconds(after attempt: Int) -> UInt64 {
        let seconds = initialDelay * pow(multiplier, Double(max(0, attempt - 1)))
        return UInt64(min(seconds * 1_000_000_000, Double(UInt64.max)))
    }
}
