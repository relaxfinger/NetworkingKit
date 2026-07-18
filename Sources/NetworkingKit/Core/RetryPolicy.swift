//
//  RetryPolicy.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// An exponential backoff policy for transient failures.
///
/// It does not retry by default to avoid unexpected side effects for non-idempotent requests.
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let multiplier: Double
    public let maximumDelay: TimeInterval
    public let jitterRatio: Double
    public let retryableMethods: Set<HTTPMethod>
    public let respectsRetryAfter: Bool

    public init(
        maxAttempts: Int = NetworkConstants.Retry.minimumAttempts,
        initialDelay: TimeInterval = NetworkConstants.Retry.defaultInitialDelay,
        multiplier: Double = NetworkConstants.Retry.defaultMultiplier,
        maximumDelay: TimeInterval = NetworkConstants.Retry.defaultMaximumDelay,
        jitterRatio: Double = NetworkConstants.Retry.defaultJitterRatio,
        retryableMethods: Set<HTTPMethod> = [.get, .head, .put, .delete, .options],
        respectsRetryAfter: Bool = true
    ) {
        self.maxAttempts = max(NetworkConstants.Retry.minimumAttempts, maxAttempts)
        self.initialDelay = max(NetworkConstants.Retry.minimumDelay, initialDelay)
        self.multiplier = max(NetworkConstants.Retry.minimumMultiplier, multiplier)
        self.maximumDelay = max(NetworkConstants.Retry.minimumDelay, maximumDelay)
        self.jitterRatio = min(1, max(0, jitterRatio))
        self.retryableMethods = retryableMethods
        self.respectsRetryAfter = respectsRetryAfter
    }

    public static let none = RetryPolicy()

    func shouldRetry(_ error: NetworkError, method: HTTPMethod) -> Bool {
        guard retryableMethods.contains(method) else { return false }
        switch error {
        case let .http(statusCode, _, _):
            return statusCode == NetworkConstants.HTTPStatus.requestTimeout
                || statusCode == NetworkConstants.HTTPStatus.tooManyRequests
                || NetworkConstants.HTTPStatus.serverErrorRange.contains(statusCode)
        case .transport: return true
        default: return false
        }
    }

    func delayNanoseconds(for error: NetworkError, after attempt: Int) -> UInt64 {
        let exponent = Double(max(NetworkConstants.Retry.minimumDelay, Double(attempt - NetworkConstants.Retry.firstAttempt)))
        let exponentialDelay = min(maximumDelay, initialDelay * pow(multiplier, exponent))
        let retryAfterDelay = respectsRetryAfter ? retryAfter(from: error) : nil
        let baseDelay = retryAfterDelay ?? exponentialDelay
        let jitteredDelay = baseDelay * (1 + Double.random(in: -jitterRatio...jitterRatio))
        let seconds = max(NetworkConstants.Retry.minimumDelay, min(maximumDelay, jitteredDelay))
        return UInt64(min(seconds * NetworkConstants.Retry.nanosecondsPerSecond, Double(UInt64.max)))
    }

    private func retryAfter(from error: NetworkError) -> TimeInterval? {
        guard case let .http(_, headers, _) = error else { return nil }
        guard let value = headers.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })?.value,
              let seconds = TimeInterval(value), seconds >= 0 else { return nil }
        return min(maximumDelay, seconds)
    }
}
