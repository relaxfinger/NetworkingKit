//
//  CachingTransport.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import CryptoKit

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
    /// Returns every cached response variant for a base request key.
    func entries(for key: String) async -> [CachedHTTPResponse]
    func store(_ entry: CachedHTTPResponse, for key: String) async
}

public extension NetworkResponseCaching {
    func entries(for key: String) async -> [CachedHTTPResponse] {
        guard let entry = await entry(for: key) else { return [] }
        return [entry]
    }
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

    func mergingRevalidationHeaders(from response: HTTPURLResponse, defaultTTL: TimeInterval) -> CachedHTTPResponse {
        let revalidationHeaders = response.headers
        let mergedHeaders = headers.merging(revalidationHeaders) { _, new in new }
        return CachedHTTPResponse(
            data: data,
            url: response.url ?? url,
            statusCode: statusCode,
            headers: mergedHeaders,
            expiresAt: CacheControl.expiry(headers: mergedHeaders, defaultTTL: defaultTTL),
            eTag: mergedHeaders.value(forHTTPHeaderField: "ETag"),
            varyHeaders: varyHeaders
        )
    }
}

/// A bounded, actor-backed in-memory response cache.
public actor InMemoryResponseCache: NetworkResponseCaching {
    private let capacity: Int
    private var values: [String: [String: CachedHTTPResponse]] = [:]
    private var keys: [String] = []

    public init(capacity: Int = 100) { self.capacity = max(1, capacity) }

    public func entry(for key: String) async -> CachedHTTPResponse? {
        guard let variants = values[key], let entry = variants.values.first else { return nil }
        touch(key)
        return entry
    }

    public func entries(for key: String) async -> [CachedHTTPResponse] {
        guard let entries = values[key]?.values else { return [] }
        touch(key)
        return Array(entries)
    }

    public func store(_ entry: CachedHTTPResponse, for key: String) async {
        if values[key] == nil, keys.count >= capacity, let oldest = keys.first {
            values.removeValue(forKey: oldest)
            keys.removeFirst()
        }
        var variants = values[key] ?? [:]
        variants[entry.variantIdentifier] = entry
        values[key] = variants
        touch(key)
    }

    private func touch(_ key: String) {
        keys.removeAll { $0 == key }
        keys.append(key)
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
        await entries(for: key).last
    }

    public func entries(for key: String) async -> [CachedHTTPResponse] {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return [] }
        if let entries = try? JSONDecoder().decode([CachedHTTPResponse].self, from: data) { return entries }
        return (try? JSONDecoder().decode(CachedHTTPResponse.self, from: data)).map { [$0] } ?? []
    }

    public func store(_ entry: CachedHTTPResponse, for key: String) async {
        var entries = await entries(for: key)
        entries.removeAll { $0.variantIdentifier == entry.variantIdentifier }
        entries.append(entry)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
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
        let requestDisallowsStorage = request.value(forHTTPHeaderField: "Cache-Control")?.lowercased().contains("no-store") == true
        let cached = request.httpMethod == HTTPMethod.get.rawValue && !requestDisallowsStorage
            ? await cache.entries(for: key).first(where: { $0.matches(request) })
            : nil
        if policy == .returnCacheDontLoad, let cached { return (cached.data, cached.makeResponse()) }
        guard policy != .returnCacheDontLoad else { throw CacheMissError() }
        if policy == .returnCacheElseLoad, let cached, cached.isFresh, !CacheControl.requiresRevalidation(cached.headers) { return (cached.data, cached.makeResponse()) }

        var request = request
        if let eTag = cached?.eTag { request.setValue(eTag, forHTTPHeaderField: "If-None-Match") }
        let result = try await upstream.send(request)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 304, let cached {
            let refreshed = cached.mergingRevalidationHeaders(from: response, defaultTTL: defaultTTL)
            await cache.store(refreshed, for: key)
            return (cached.data, refreshed.makeResponse())
        }
        if request.httpMethod == HTTPMethod.get.rawValue,
           let response = result.1 as? HTTPURLResponse,
           NetworkConstants.HTTPStatus.successRange.contains(response.statusCode), !requestDisallowsStorage,
           !isNoStore(response), !response.variesByAllHeaders {
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
        let eTag = headers.value(forHTTPHeaderField: "ETag")
        let vary = headers.value(forHTTPHeaderField: "Vary")
        let varyHeaders = Dictionary(uniqueKeysWithValues: (vary?.split(separator: ",") ?? []).map { name in
            let field = name.trimmingCharacters(in: .whitespaces)
            return (field, request.value(forHTTPHeaderField: field) ?? "")
        })
        return CachedHTTPResponse(data: data, url: response.url ?? fallbackURL!, statusCode: response.statusCode, headers: headers, expiresAt: CacheControl.expiry(headers: headers, defaultTTL: defaultTTL), eTag: eTag, varyHeaders: varyHeaders)
    }

    private func isNoStore(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "Cache-Control")?.lowercased().contains("no-store") == true
    }

}

private enum CacheControl {
    static func requiresRevalidation(_ headers: [String: String]) -> Bool {
        headers.value(forHTTPHeaderField: "Cache-Control")?.lowercased().contains("no-cache") == true
    }

    static func expiry(headers: [String: String], defaultTTL: TimeInterval) -> Date {
        let control = headers.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
        if control.contains("no-cache") { return Date() }
        let maxAge = control.split(separator: ",").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("max-age=") }
            .flatMap { TimeInterval($0.split(separator: "=").last ?? "") }
        let expires = headers.value(forHTTPHeaderField: "Expires").flatMap(parseHTTPDate)
        return Date().addingTimeInterval(maxAge ?? expires.map { $0.timeIntervalSinceNow } ?? defaultTTL)
    }

    private static func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value)
    }
}

private extension CachedHTTPResponse {
    var variantIdentifier: String {
        varyHeaders.sorted { $0.key < $1.key }.map { "\($0.key.lowercased())=\($0.value)" }.joined(separator: "&")
    }
}

private extension Dictionary where Key == String, Value == String {
    func value(forHTTPHeaderField field: String) -> String? {
        first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}

private extension HTTPURLResponse {
    var headers: [String: String] {
        allHeaderFields.reduce(into: [:]) { result, item in
            if let key = item.key as? String { result[key] = String(describing: item.value) }
        }
    }

    var variesByAllHeaders: Bool {
        value(forHTTPHeaderField: "Vary")?.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "*" } == true
    }
}

/// Indicates an offline cache-only request had no matching entry.
public struct CacheMissError: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "No cached response is available" }
}
