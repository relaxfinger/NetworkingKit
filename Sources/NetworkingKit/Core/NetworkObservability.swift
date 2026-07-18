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
