//
//  CachePerformanceTests.swift
//  NetworkingKitTests
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
@testable import NetworkingKit

final class CachePerformanceTests: XCTestCase {
    func testRequestLevelPolicyOverridesTransportDefault() async throws {
        let attempts = AsyncAttemptCounter()
        let upstream = AsyncStubTransport { request in
            let attempt = await attempts.increment()
            return (
                Data(#"{"value":\#(attempt)}"#.utf8),
                HTTPURLResponse(
                    url: try! XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Cache-Control": "max-age=60"]
                )!
            )
        }
        let client = CacheTestClient(
            transport: RequestCoalescingTransport(
                upstream: CachingTransport(
                    upstream: upstream,
                    cache: InMemoryResponseCache(),
                    policy: .returnCacheElseLoad
                )
            )
        )

        let first = try await CacheValueRequest(client: client).execute()
        let cached = try await CacheValueRequest(client: client).execute()
        let refreshed = try await CacheValueRequest(
            client: client,
            cachePolicy: .networkOnly
        ).execute()

        XCTAssertEqual(first.value, 1)
        XCTAssertEqual(cached.value, 1)
        XCTAssertEqual(refreshed.value, 2)
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 2)
    }

    func testStaleWhileRevalidateReturnsStaleAndRefreshesCache() async throws {
        let url = URL(string: "https://example.com/value")!
        let cache = InMemoryResponseCache()
        await cache.store(
            CachedHTTPResponse(
                data: Data("stale".utf8),
                url: url,
                statusCode: 200,
                headers: ["Cache-Control": "max-age=0", "ETag": "v1"],
                expiresAt: Date().addingTimeInterval(-10),
                eTag: "v1",
                varyHeaders: [:]
            ),
            for: "GET https://example.com/value"
        )
        let attempts = AsyncAttemptCounter()
        let upstream = AsyncStubTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "v1")
            _ = await attempts.increment()
            return (
                Data("fresh".utf8),
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Cache-Control": "max-age=60", "ETag": "v2"]
                )!
            )
        }
        let transport = CachingTransport(
            upstream: upstream,
            cache: cache,
            policy: .staleWhileRevalidate(maxStale: 60)
        )

        let immediate = try await transport.send(URLRequest(url: url))

        XCTAssertEqual(String(data: immediate.0, encoding: .utf8), "stale")
        await waitUntil {
            let entry = await cache.entry(for: "GET https://example.com/value")
            return entry.map { String(data: $0.data, encoding: .utf8) } == "fresh"
        }
        let refreshed = await cache.entry(for: "GET https://example.com/value")
        XCTAssertEqual(refreshed.map { String(data: $0.data, encoding: .utf8) }, "fresh")
    }

    func testStaleWhileRevalidateWaitsWhenEntryIsTooOld() async throws {
        let url = URL(string: "https://example.com/value")!
        let cache = InMemoryResponseCache()
        await cache.store(
            CachedHTTPResponse(
                data: Data("too-old".utf8),
                url: url,
                statusCode: 200,
                headers: [:],
                expiresAt: Date().addingTimeInterval(-120),
                eTag: nil,
                varyHeaders: [:]
            ),
            for: "GET https://example.com/value"
        )
        let transport = CachingTransport(
            upstream: AsyncStubTransport { request in
                (
                    Data("fresh".utf8),
                    HTTPURLResponse(
                        url: try! XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            },
            cache: cache,
            policy: .staleWhileRevalidate(maxStale: 30)
        )

        let result = try await transport.send(URLRequest(url: url))

        XCTAssertEqual(String(data: result.0, encoding: .utf8), "fresh")
    }

    func testCoalescingTransportSharesEquivalentConcurrentGET() async throws {
        let attempts = AsyncAttemptCounter()
        let upstream = AsyncStubTransport { request in
            _ = await attempts.increment()
            try await Task.sleep(for: .milliseconds(50))
            return (
                Data("shared".utf8),
                HTTPURLResponse(
                    url: try! XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let transport = RequestCoalescingTransport(upstream: upstream)
        let request = URLRequest(url: URL(string: "https://example.com/shared")!)

        async let first = transport.send(request)
        async let second = transport.send(request)
        let results = try await [first, second]

        XCTAssertEqual(results.map { String(data: $0.0, encoding: .utf8) }, ["shared", "shared"])
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 1)
    }

    func testCoalescingKeySeparatesAuthorizationVariants() async throws {
        let attempts = AsyncAttemptCounter()
        let upstream = AsyncStubTransport { request in
            _ = await attempts.increment()
            try await Task.sleep(for: .milliseconds(20))
            return (
                Data(),
                HTTPURLResponse(
                    url: try! XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let transport = RequestCoalescingTransport(upstream: upstream)
        let url = URL(string: "https://example.com/profile")!
        var firstRequest = URLRequest(url: url)
        firstRequest.setValue("Bearer first", forHTTPHeaderField: "Authorization")
        var secondRequest = URLRequest(url: url)
        secondRequest.setValue("Bearer second", forHTTPHeaderField: "Authorization")

        async let first = transport.send(firstRequest)
        async let second = transport.send(secondRequest)
        _ = try await [first, second]

        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 2)
    }

    func testCoalescingTransportSeparatesCachePolicyVariants() async throws {
        let attempts = AsyncAttemptCounter()
        let upstream = PolicyAwareStubTransport { request, policy in
            _ = await attempts.increment()
            try await Task.sleep(for: .milliseconds(20))
            return (
                Data(String(describing: policy).utf8),
                HTTPURLResponse(
                    url: try! XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let transport = RequestCoalescingTransport(upstream: upstream)
        let request = URLRequest(url: URL(string: "https://example.com/profile")!)

        async let cached = transport.send(request, cachePolicy: .returnCacheDontLoad)
        async let network = transport.send(request, cachePolicy: .networkOnly)
        let results = try await [cached, network]

        XCTAssertNotEqual(results[0].0, results[1].0)
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 2)
    }

    func testCoalescingTransportDoesNotSharePOSTRequests() async throws {
        let attempts = AsyncAttemptCounter()
        let upstream = AsyncStubTransport { request in
            _ = await attempts.increment()
            try await Task.sleep(for: .milliseconds(20))
            return (
                Data(),
                HTTPURLResponse(
                    url: try! XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let transport = RequestCoalescingTransport(upstream: upstream)
        var request = URLRequest(url: URL(string: "https://example.com/write")!)
        request.httpMethod = HTTPMethod.post.rawValue
        let firstRequest = request
        let secondRequest = request

        async let first = transport.send(firstRequest)
        async let second = transport.send(secondRequest)
        _ = try await [first, second]

        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 2)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true before timeout")
    }
}

private struct CacheValue: Decodable, Sendable {
    let value: Int
}

private struct CacheValueRequest: RestfulRequest {
    typealias Response = CacheValue

    let client: CacheTestClient
    let cachePolicy: NetworkCachePolicy?
    let path = "value"
    let method = HTTPMethod.get
    let queryItems: [URLQueryItem]? = nil
    let body: (any Encodable & Sendable)? = nil
    let contentType: String? = nil

    init(client: CacheTestClient, cachePolicy: NetworkCachePolicy? = nil) {
        self.client = client
        self.cachePolicy = cachePolicy
    }
}

private final class CacheTestClient: NetworkClient, @unchecked Sendable {
    let baseURL = URL(string: "https://example.com")!
    let session = URLSession(configuration: .ephemeral)
    let defaultProfile = NetworkClientProfile()
    let transport: any NetworkTransport

    init(transport: any NetworkTransport) {
        self.transport = transport
    }
}

private struct AsyncStubTransport: NetworkTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let handler: Handler

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private struct PolicyAwareStubTransport: RequestCachePolicyTransport {
    typealias Handler = @Sendable (
        URLRequest,
        NetworkCachePolicy?
    ) async throws -> (Data, URLResponse)
    let handler: Handler

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request, nil)
    }

    func send(
        _ request: URLRequest,
        cachePolicy: NetworkCachePolicy?
    ) async throws -> (Data, URLResponse) {
        try await handler(request, cachePolicy)
    }
}

private actor AsyncAttemptCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
