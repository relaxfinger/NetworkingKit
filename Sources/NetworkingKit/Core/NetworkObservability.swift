//
//  NetworkObservability.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Identifies one network attempt for logging, tracing, and metrics.
public struct NetworkRequestContext: Sendable {
    public let id: String
    public let method: HTTPMethod
    public let url: URL

    public init(id: String, method: HTTPMethod, url: URL) {
        self.id = id
        self.method = method
        self.url = url
    }
}

/// Describes the result of one network attempt.
public struct NetworkRequestOutcome: Sendable {
    public let statusCode: Int?
    public let duration: TimeInterval
    public let error: NetworkError?

    public init(statusCode: Int?, duration: TimeInterval, error: NetworkError?) {
        self.statusCode = statusCode
        self.duration = duration
        self.error = error
    }
}

/// A lifecycle event emitted for every transport attempt.
public enum NetworkEvent: Sendable {
    case started(NetworkRequestContext)
    case finished(NetworkRequestContext, NetworkRequestOutcome)
}

/// Receives network lifecycle events without coupling NetworkingKit to a telemetry vendor.
public protocol NetworkObserving: Sendable {
    /// Records a network lifecycle event.
    func record(_ event: NetworkEvent) async
}

/// A point-in-time aggregate of completed network attempts.
public struct NetworkMetricsSnapshot: Sendable, Equatable {
    /// The total number of completed attempts.
    public let totalCount: Int
    /// The number of attempts that completed without a `NetworkError`.
    public let successCount: Int
    /// The number of attempts that completed with a `NetworkError`.
    public let failureCount: Int
    /// The number of failures without an HTTP status code.
    public let transportFailureCount: Int
    /// A histogram of observed HTTP status codes.
    public let statusCodeCounts: [Int: Int]
    /// The arithmetic mean attempt duration in seconds.
    public let averageDuration: TimeInterval

    /// Creates a metrics snapshot.
    public init(totalCount: Int, successCount: Int, failureCount: Int, transportFailureCount: Int, statusCodeCounts: [Int: Int], averageDuration: TimeInterval) {
        self.totalCount = totalCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.transportFailureCount = transportFailureCount
        self.statusCodeCounts = statusCodeCounts
        self.averageDuration = averageDuration
    }
}

/// Collects aggregate network-attempt metrics safely across concurrent requests.
public actor NetworkMetrics {
    private var totalCount = 0
    private var successCount = 0
    private var failureCount = 0
    private var transportFailureCount = 0
    private var statusCodeCounts: [Int: Int] = [:]
    private var totalDuration: TimeInterval = 0

    /// Creates an empty metrics collector.
    public init() {}

    /// Records one completed network attempt.
    public func record(_ outcome: NetworkRequestOutcome) {
        totalCount += 1
        totalDuration += outcome.duration
        if outcome.error == nil { successCount += 1 } else { failureCount += 1 }
        if let statusCode = outcome.statusCode {
            statusCodeCounts[statusCode, default: 0] += 1
        } else if outcome.error != nil {
            transportFailureCount += 1
        }
    }

    /// Returns the current aggregate metrics without clearing them.
    public func snapshot() -> NetworkMetricsSnapshot {
        NetworkMetricsSnapshot(totalCount: totalCount, successCount: successCount, failureCount: failureCount, transportFailureCount: transportFailureCount, statusCodeCounts: statusCodeCounts, averageDuration: totalCount == 0 ? 0 : totalDuration / Double(totalCount))
    }

    /// Clears all collected metrics.
    public func reset() {
        totalCount = 0
        successCount = 0
        failureCount = 0
        transportFailureCount = 0
        statusCodeCounts = [:]
        totalDuration = 0
    }
}

/// Forwards completed lifecycle events to a `NetworkMetrics` collector.
public struct NetworkMetricsObserver: NetworkObserving {
    private let metrics: NetworkMetrics

    /// Creates an observer that records into `metrics`.
    public init(metrics: NetworkMetrics) { self.metrics = metrics }

    public func record(_ event: NetworkEvent) async {
        guard case let .finished(_, outcome) = event else { return }
        await metrics.record(outcome)
    }
}

/// Adds a stable correlation identifier to every request that does not already have one.
public struct RequestIDInterceptor: NetworkInterceptor {
    public let headerField: String
    private let identifier: @Sendable () -> String

    public init(
        headerField: String = "X-Request-ID",
        identifier: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.headerField = headerField
        self.identifier = identifier
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        guard request.value(forHTTPHeaderField: headerField) == nil else { return request }
        var request = request
        request.setValue(identifier(), forHTTPHeaderField: headerField)
        return request
    }
}
