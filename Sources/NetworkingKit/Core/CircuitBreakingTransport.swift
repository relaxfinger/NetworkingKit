//
//  CircuitBreakingTransport.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// The current state of a circuit breaker.
public enum CircuitBreakerState: String, Sendable, Equatable {
    /// Requests are allowed and failures are counted.
    case closed
    /// Requests are rejected until the reset timeout expires.
    case open
    /// Exactly one recovery request is in progress.
    case halfOpen
}

/// A point-in-time, sendable view of a circuit breaker's state.
public struct CircuitBreakerSnapshot: Sendable, Equatable {
    /// The circuit's current state.
    public let state: CircuitBreakerState
    /// The number of consecutive failures recorded for the current circuit.
    public let consecutiveFailures: Int

    /// Creates a circuit-breaker snapshot.
    public init(state: CircuitBreakerState, consecutiveFailures: Int) {
        self.state = state
        self.consecutiveFailures = consecutiveFailures
    }
}

/// Opens after repeated failures to prevent requests from amplifying an unavailable service.
///
/// After `resetTimeout` expires, the breaker enters the half-open state and permits one probe.
/// A successful probe closes the circuit; a failed probe opens it again.
public actor CircuitBreaker {
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private var consecutiveFailures = 0
    private var state: CircuitBreakerState = .closed
    private var openedAt: Date?

    /// Creates a circuit breaker.
    ///
    /// - Parameters:
    ///   - failureThreshold: Consecutive failures required to open the circuit.
    ///   - resetTimeout: Time to wait before allowing a single recovery probe.
    public init(failureThreshold: Int = 5, resetTimeout: TimeInterval = 30) {
        self.failureThreshold = max(1, failureThreshold)
        self.resetTimeout = max(0, resetTimeout)
    }

    /// Allows the next request or throws when the circuit is open.
    public func allowRequest() throws {
        switch state {
        case .closed:
            return
        case .halfOpen:
            throw CircuitOpenError()
        case .open:
            guard let openedAt else {
                state = .halfOpen
                return
            }
            guard Date().timeIntervalSince(openedAt) >= resetTimeout else {
                throw CircuitOpenError()
            }
            state = .halfOpen
        }
    }

    /// Records a successful request and closes the circuit.
    public func recordSuccess() {
        consecutiveFailures = 0
        state = .closed
        openedAt = nil
    }

    /// Records a failed request and opens the circuit when its threshold is reached.
    public func recordFailure() {
        consecutiveFailures += 1
        if state == .halfOpen || consecutiveFailures >= failureThreshold {
            state = .open
            openedAt = Date()
        }
    }

    /// Returns the circuit's current state and failure count.
    public func snapshot() -> CircuitBreakerSnapshot {
        CircuitBreakerSnapshot(state: state, consecutiveFailures: consecutiveFailures)
    }
}

/// Provides stable route keys for route-scoped circuit breakers.
public enum CircuitBreakerRouteKey {
    /// Returns a key consisting of the HTTP method, host, port, and URL path.
    ///
    /// Query parameters are intentionally excluded so equivalent endpoint requests share a circuit.
    public static func hostAndPath(for request: URLRequest) -> String {
        let method = request.httpMethod ?? HTTPMethod.get.rawValue
        let host = request.url?.host ?? ""
        let port = request.url?.port.map(String.init) ?? ""
        let path = request.url?.path ?? ""
        return "\(method) \(host):\(port)\(path)"
    }
}

/// Stores independent circuit breakers for endpoint routes.
public actor CircuitBreakerRegistry {
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private var breakers: [String: CircuitBreaker] = [:]

    /// Creates a registry whose new circuits share these settings.
    public init(failureThreshold: Int = 5, resetTimeout: TimeInterval = 30) {
        self.failureThreshold = max(1, failureThreshold)
        self.resetTimeout = max(0, resetTimeout)
    }

    /// Returns the circuit breaker associated with a route key, creating it if necessary.
    public func circuit(for routeKey: String) -> CircuitBreaker {
        if let breaker = breakers[routeKey] { return breaker }
        let breaker = CircuitBreaker(failureThreshold: failureThreshold, resetTimeout: resetTimeout)
        breakers[routeKey] = breaker
        return breaker
    }

    /// Returns current state snapshots indexed by route key.
    public func snapshots() async -> [String: CircuitBreakerSnapshot] {
        var result: [String: CircuitBreakerSnapshot] = [:]
        for (key, breaker) in breakers {
            result[key] = await breaker.snapshot()
        }
        return result
    }
}

/// Wraps a transport with a single circuit breaker.
public struct CircuitBreakingTransport: NetworkTransport {
    /// The transport protected by the circuit breaker.
    public let upstream: any NetworkTransport
    /// The circuit breaker shared by all requests through this transport.
    public let circuitBreaker: CircuitBreaker

    /// Creates a transport protected by one circuit breaker.
    public init(upstream: any NetworkTransport, circuitBreaker: CircuitBreaker = CircuitBreaker()) {
        self.upstream = upstream
        self.circuitBreaker = circuitBreaker
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await circuitBreaker.allowRequest()
        return try await send(request, through: circuitBreaker)
    }

    private func send(_ request: URLRequest, through breaker: CircuitBreaker) async throws -> (Data, URLResponse) {
        do {
            let result = try await upstream.send(request)
            if let response = result.1 as? HTTPURLResponse, response.statusCode >= 500 {
                await breaker.recordFailure()
            } else {
                await breaker.recordSuccess()
            }
            return result
        } catch {
            await breaker.recordFailure()
            throw error
        }
    }
}

/// Wraps a transport with independently recovering circuit breakers for each route.
public struct RouteCircuitBreakingTransport: NetworkTransport {
    /// The transport protected by route-specific circuit breakers.
    public let upstream: any NetworkTransport
    /// The registry that owns route-specific circuit breakers and their metrics.
    public let registry: CircuitBreakerRegistry
    private let routeKey: @Sendable (URLRequest) -> String

    /// Creates a route-scoped circuit-breaking transport.
    ///
    /// - Parameters:
    ///   - upstream: The transport to protect.
    ///   - registry: The registry used to create and inspect route circuits.
    ///   - routeKey: Maps requests to a route key. The default isolates method, host, port, and path.
    public init(
        upstream: any NetworkTransport,
        registry: CircuitBreakerRegistry = CircuitBreakerRegistry(),
        routeKey: @escaping @Sendable (URLRequest) -> String = CircuitBreakerRouteKey.hostAndPath(for:)
    ) {
        self.upstream = upstream
        self.registry = registry
        self.routeKey = routeKey
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let breaker = await registry.circuit(for: routeKey(request))
        try await breaker.allowRequest()
        do {
            let result = try await upstream.send(request)
            if let response = result.1 as? HTTPURLResponse, response.statusCode >= 500 {
                await breaker.recordFailure()
            } else {
                await breaker.recordSuccess()
            }
            return result
        } catch {
            await breaker.recordFailure()
            throw error
        }
    }
}

/// Indicates a circuit breaker rejected an attempt while the service recovers.
public struct CircuitOpenError: LocalizedError, Sendable {
    /// Creates a circuit-open error.
    public init() {}

    public var errorDescription: String? { "Network circuit is open" }
}
