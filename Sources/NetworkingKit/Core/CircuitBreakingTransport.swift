//
//  CircuitBreakingTransport.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Opens after repeated failures to prevent requests from amplifying an unavailable service.
public actor CircuitBreaker {
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private var failures = 0
    private var openedAt: Date?

    public init(failureThreshold: Int = 5, resetTimeout: TimeInterval = 30) {
        self.failureThreshold = max(1, failureThreshold)
        self.resetTimeout = max(1, resetTimeout)
    }

    func allowRequest() throws {
        if let openedAt, Date().timeIntervalSince(openedAt) < resetTimeout { throw CircuitOpenError() }
        if openedAt != nil { self.openedAt = nil; failures = 0 }
    }

    func recordSuccess() { failures = 0; openedAt = nil }

    func recordFailure() {
        failures += 1
        if failures >= failureThreshold { openedAt = Date() }
    }
}

/// Wraps a transport with a circuit breaker.
public struct CircuitBreakingTransport: NetworkTransport {
    public let upstream: any NetworkTransport
    public let circuitBreaker: CircuitBreaker

    public init(upstream: any NetworkTransport, circuitBreaker: CircuitBreaker = CircuitBreaker()) {
        self.upstream = upstream
        self.circuitBreaker = circuitBreaker
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await circuitBreaker.allowRequest()
        do {
            let result = try await upstream.send(request)
            if let response = result.1 as? HTTPURLResponse, response.statusCode >= 500 { await circuitBreaker.recordFailure() }
            else { await circuitBreaker.recordSuccess() }
            return result
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }
}

/// Indicates a circuit breaker rejected an attempt while the service recovers.
public struct CircuitOpenError: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "Network circuit is open" }
}
