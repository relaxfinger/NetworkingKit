//
//  CachingTransport.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Controls how a `CachingTransport` resolves GET requests.
public enum NetworkCachePolicy: Sendable, Equatable {
    /// Always use the upstream transport.
    case networkOnly
    /// Use a cached response when available, otherwise use the upstream transport.
    case returnCacheElseLoad
    /// Use a cached response and fail when no entry exists; suitable for offline mode.
    case returnCacheDontLoad
}

/// Stores cached transport responses.
public protocol NetworkResponseCaching: Sendable {
    func response(for key: String) async -> (Data, HTTPURLResponse)?
    func store(_ data: Data, response: HTTPURLResponse, for key: String) async
}

/// A bounded, actor-backed in-memory response cache.
public actor InMemoryResponseCache: NetworkResponseCaching {
    private let capacity: Int
    private var values: [String: (Data, HTTPURLResponse)] = [:]
    private var keys: [String] = []

    public init(capacity: Int = 100) { self.capacity = max(1, capacity) }

    public func response(for key: String) async -> (Data, HTTPURLResponse)? { values[key] }

    public func store(_ data: Data, response: HTTPURLResponse, for key: String) async {
        if values[key] == nil, keys.count >= capacity, let oldest = keys.first {
            values.removeValue(forKey: oldest)
            keys.removeFirst()
        }
        keys.removeAll { $0 == key }
        keys.append(key)
        values[key] = (data, response)
    }
}

/// Wraps another transport with a cache for successful GET responses.
public struct CachingTransport: NetworkTransport {
    public let upstream: any NetworkTransport
    public let cache: any NetworkResponseCaching
    public let policy: NetworkCachePolicy

    public init(upstream: any NetworkTransport, cache: any NetworkResponseCaching, policy: NetworkCachePolicy = .returnCacheElseLoad) {
        self.upstream = upstream
        self.cache = cache
        self.policy = policy
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let key = cacheKey(for: request)
        if request.httpMethod == HTTPMethod.get.rawValue, policy != .networkOnly,
           let cached = await cache.response(for: key) {
            return cached
        }
        guard policy != .returnCacheDontLoad else { throw CacheMissError() }
        let result = try await upstream.send(request)
        if request.httpMethod == HTTPMethod.get.rawValue,
           let response = result.1 as? HTTPURLResponse,
           NetworkConstants.HTTPStatus.successRange.contains(response.statusCode) {
            await cache.store(result.0, response: response, for: key)
        }
        return result
    }

    private func cacheKey(for request: URLRequest) -> String {
        "\(request.httpMethod ?? HTTPMethod.get.rawValue) \(request.url?.absoluteString ?? "")"
    }
}

/// Indicates an offline cache-only request had no matching entry.
public struct CacheMissError: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "No cached response is available" }
}
