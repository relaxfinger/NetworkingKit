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
    func entry(for key: String) async -> CachedHTTPResponse?
    func store(_ entry: CachedHTTPResponse, for key: String) async
}

/// A cached HTTP response with its expiry and revalidation metadata.
public struct CachedHTTPResponse: Sendable, Codable {
    public let data: Data
    public let url: URL
    public let statusCode: Int
    public let headers: [String: String]
    public let expiresAt: Date
    public let eTag: String?
    public let varyHeaders: [String: String]

    public var isFresh: Bool { expiresAt > Date() }

    func makeResponse() -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
    }

    func matches(_ request: URLRequest) -> Bool {
        varyHeaders.allSatisfy { request.value(forHTTPHeaderField: $0.key) == $0.value }
    }
}

/// A bounded, actor-backed in-memory response cache.
public actor InMemoryResponseCache: NetworkResponseCaching {
    private let capacity: Int
    private var values: [String: CachedHTTPResponse] = [:]
    private var keys: [String] = []

    public init(capacity: Int = 100) { self.capacity = max(1, capacity) }

    public func entry(for key: String) async -> CachedHTTPResponse? {
        guard let entry = values[key] else { return nil }
        keys.removeAll { $0 == key }
        keys.append(key)
        return entry
    }

    public func store(_ entry: CachedHTTPResponse, for key: String) async {
        if values[key] == nil, keys.count >= capacity, let oldest = keys.first {
            values.removeValue(forKey: oldest)
            keys.removeFirst()
        }
        keys.removeAll { $0 == key }
        keys.append(key)
        values[key] = entry
    }
}

/// A JSON-backed cache that persists entries across app launches.
public actor DiskResponseCache: NetworkResponseCaching {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func entry(for key: String) async -> CachedHTTPResponse? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode(CachedHTTPResponse.self, from: data)
    }

    public func store(_ entry: CachedHTTPResponse, for key: String) async {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        let name = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}

/// Wraps another transport with a cache for successful GET responses.
public struct CachingTransport: NetworkTransport {
    public let upstream: any NetworkTransport
    public let cache: any NetworkResponseCaching
    public let policy: NetworkCachePolicy
    public let defaultTTL: TimeInterval

    public init(upstream: any NetworkTransport, cache: any NetworkResponseCaching, policy: NetworkCachePolicy = .returnCacheElseLoad, defaultTTL: TimeInterval = 300) {
        self.upstream = upstream
        self.cache = cache
        self.policy = policy
        self.defaultTTL = max(0, defaultTTL)
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let key = cacheKey(for: request)
        let stored = request.httpMethod == HTTPMethod.get.rawValue ? await cache.entry(for: key) : nil
        let cached = stored?.matches(request) == true ? stored : nil
        if policy == .returnCacheDontLoad, let cached { return (cached.data, cached.makeResponse()) }
        guard policy != .returnCacheDontLoad else { throw CacheMissError() }
        if policy == .returnCacheElseLoad, let cached, cached.isFresh { return (cached.data, cached.makeResponse()) }

        var request = request
        if let eTag = cached?.eTag { request.setValue(eTag, forHTTPHeaderField: "If-None-Match") }
        let result = try await upstream.send(request)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 304, let cached {
            let refreshed = makeEntry(data: cached.data, response: response, request: request, fallbackURL: cached.url)
            await cache.store(refreshed, for: key)
            return (cached.data, refreshed.makeResponse())
        }
        if request.httpMethod == HTTPMethod.get.rawValue,
           let response = result.1 as? HTTPURLResponse,
           NetworkConstants.HTTPStatus.successRange.contains(response.statusCode), !isNoStore(response) {
            await cache.store(makeEntry(data: result.0, response: response, request: request, fallbackURL: request.url), for: key)
        }
        return result
    }

    private func cacheKey(for request: URLRequest) -> String {
        "\(request.httpMethod ?? HTTPMethod.get.rawValue) \(request.url?.absoluteString ?? "")"
    }

    private func makeEntry(data: Data, response: HTTPURLResponse, request: URLRequest, fallbackURL: URL?) -> CachedHTTPResponse {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String { result[key] = String(describing: item.value) }
        }
        let cacheControl = headers.first { $0.key.caseInsensitiveCompare("Cache-Control") == .orderedSame }?.value
        let directive = cacheControl?.split(separator: ",").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("max-age=")
        }
        let maxAgeValue = directive?.split(separator: "=").last.map(String.init)
        let expiresValue = headers.first { $0.key.caseInsensitiveCompare("Expires") == .orderedSame }?.value
        let expires = expiresValue.flatMap { parseHTTPDate($0) }
        let maxAge = maxAgeValue.flatMap(TimeInterval.init) ?? expires.map { $0.timeIntervalSinceNow } ?? defaultTTL
        let eTag = headers.first { $0.key.caseInsensitiveCompare("ETag") == .orderedSame }?.value
        let vary = headers.first { $0.key.caseInsensitiveCompare("Vary") == .orderedSame }?.value
        let varyHeaders = Dictionary(uniqueKeysWithValues: (vary?.split(separator: ",") ?? []).map { name in
            let field = name.trimmingCharacters(in: .whitespaces)
            return (field, request.value(forHTTPHeaderField: field) ?? "")
        })
        return CachedHTTPResponse(data: data, url: response.url ?? fallbackURL!, statusCode: response.statusCode, headers: headers, expiresAt: Date().addingTimeInterval(maxAge), eTag: eTag, varyHeaders: varyHeaders)
    }

    private func isNoStore(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "Cache-Control")?.lowercased().contains("no-store") == true
    }

    private func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value)
    }
}

/// Indicates an offline cache-only request had no matching entry.
public struct CacheMissError: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "No cached response is available" }
}
