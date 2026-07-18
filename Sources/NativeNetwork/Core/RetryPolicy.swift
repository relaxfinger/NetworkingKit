//
//  RetryPolicy.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
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

    public init(maxAttempts: Int = NetworkConstants.Retry.minimumAttempts, initialDelay: TimeInterval = NetworkConstants.Retry.defaultInitialDelay, multiplier: Double = NetworkConstants.Retry.defaultMultiplier) {
        self.maxAttempts = max(NetworkConstants.Retry.minimumAttempts, maxAttempts)
        self.initialDelay = max(NetworkConstants.Retry.minimumDelay, initialDelay)
        self.multiplier = max(NetworkConstants.Retry.minimumMultiplier, multiplier)
    }

    public static let none = RetryPolicy()

    func shouldRetry(_ error: NetworkError) -> Bool {
        switch error {
        case let .http(statusCode, _, _):
            return statusCode == NetworkConstants.HTTPStatus.requestTimeout
                || statusCode == NetworkConstants.HTTPStatus.tooManyRequests
                || NetworkConstants.HTTPStatus.serverErrorRange.contains(statusCode)
        case .transport: return true
        default: return false
        }
    }

    func delayNanoseconds(after attempt: Int) -> UInt64 {
        let exponent = Double(max(NetworkConstants.Retry.minimumDelay, Double(attempt - NetworkConstants.Retry.firstAttempt)))
        let seconds = initialDelay * pow(multiplier, exponent)
        return UInt64(min(seconds * NetworkConstants.Retry.nanosecondsPerSecond, Double(UInt64.max)))
    }
}
