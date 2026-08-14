//
//  RequestCoalescingTransport.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import CryptoKit
import Foundation

/// Coalesces concurrent equivalent idempotent requests into one upstream attempt.
///
/// The default key includes every request header except correlation and distributed-
/// tracing headers. Header values are hashed and are never exposed by the transport.
public struct RequestCoalescingTransport: RequestCachePolicyTransport {
    public typealias KeyProvider = @Sendable (URLRequest) -> String

    public let upstream: any NetworkTransport
    public let methods: Set<HTTPMethod>
    private let coordinator: RequestCoalescingCoordinator
    private let keyProvider: KeyProvider

    public init(
        upstream: any NetworkTransport,
        methods: Set<HTTPMethod> = [.get, .head],
        keyProvider: @escaping KeyProvider = RequestCoalescingKey.default
    ) {
        self.upstream = upstream
        self.methods = methods
        self.keyProvider = keyProvider
        coordinator = RequestCoalescingCoordinator()
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await send(request, cachePolicy: nil)
    }

    public func send(
        _ request: URLRequest,
        cachePolicy: NetworkCachePolicy?
    ) async throws -> (Data, URLResponse) {
        guard let rawMethod = request.httpMethod,
              let method = HTTPMethod(rawValue: rawMethod),
              methods.contains(method)
        else {
            return try await sendUpstream(request, cachePolicy: cachePolicy)
        }

        let key = "\(keyProvider(request))\ncache-policy:\(cachePolicy.coalescingKey)"
        return try await coordinator.execute(key: key) {
            try await sendUpstream(request, cachePolicy: cachePolicy)
        }
    }

    private func sendUpstream(
        _ request: URLRequest,
        cachePolicy: NetworkCachePolicy?
    ) async throws -> (Data, URLResponse) {
        if let upstream = upstream as? any RequestCachePolicyTransport {
            return try await upstream.send(request, cachePolicy: cachePolicy)
        }
        return try await upstream.send(request)
    }
}

private extension Optional where Wrapped == NetworkCachePolicy {
    var coalescingKey: String {
        switch self {
        case nil: "default"
        case .some(.networkOnly): "network-only"
        case .some(.returnCacheElseLoad): "return-cache-else-load"
        case .some(.returnCacheDontLoad): "return-cache-dont-load"
        case let .some(.staleWhileRevalidate(maxStale)): "stale-while-revalidate:\(maxStale)"
        }
    }
}

/// Builds privacy-safe keys for request coalescing.
public enum RequestCoalescingKey {
    /// Includes the method, absolute URL, and response-affecting request headers.
    /// Correlation and tracing headers are excluded so observability does not defeat coalescing.
    public static func `default`(_ request: URLRequest) -> String {
        let ignoredHeaders = Set([
            "x-request-id",
            "traceparent",
            "tracestate"
        ])
        let headers = request.allHTTPHeaderFields ?? [:]
        let canonicalHeaders = headers
            .filter { !ignoredHeaders.contains($0.key.lowercased()) }
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key.lowercased()):\($0.value)" }
            .joined(separator: "\n")
        let canonical = [
            request.httpMethod ?? HTTPMethod.get.rawValue,
            request.url?.absoluteString ?? "",
            canonicalHeaders
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private actor RequestCoalescingCoordinator {
    private struct SharedResponse: @unchecked Sendable {
        let data: Data
        let response: URLResponse
    }

    private var inFlight: [String: Task<SharedResponse, Error>] = [:]

    func execute(
        key: String,
        operation: @escaping @Sendable () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        if let task = inFlight[key] {
            let result = try await task.value
            try Task.checkCancellation()
            return (result.data, result.response)
        }

        let task = Task {
            let result = try await operation()
            return SharedResponse(data: result.0, response: result.1)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let result = try await task.value
        try Task.checkCancellation()
        return (result.data, result.response)
    }
}
