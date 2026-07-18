//
//  NetworkExecutionControl.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Controls admission to a network attempt.
public protocol NetworkExecutionControlling: Sendable {
    /// Waits until an attempt may begin.
    func acquire() async

    /// Releases an attempt slot.
    func release() async
}

/// An actor-backed limit for concurrent network attempts.
public actor RequestConcurrencyLimiter: NetworkExecutionControlling {
    private let maximumConcurrentRequests: Int
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a limiter with a positive concurrent-attempt limit.
    public init(maximumConcurrentRequests: Int) {
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
    }

    public func acquire() async {
        guard activeRequests >= maximumConcurrentRequests else {
            activeRequests += 1
            return
        }
        await withCheckedContinuation { continuation in waiters.append(continuation) }
        activeRequests += 1
    }

    public func release() async {
        activeRequests = max(0, activeRequests - 1)
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}
