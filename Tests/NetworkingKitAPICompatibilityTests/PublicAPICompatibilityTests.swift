//
//  PublicAPICompatibilityTests.swift
//  NetworkingKitAPICompatibilityTests
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
import NetworkingKit

/// Compiles representative third-party integration code against public APIs only.
///
/// Keep this fixture free of `@testable import` so source-breaking public API changes fail in CI.
final class PublicAPICompatibilityTests: XCTestCase {
    func testThirdPartyIntegrationCompiles() async throws {
        let client = CompatibilityClient()
        let restRequest = CompatibilityRESTRequest(client: client)
        let graphQLRequest = CompatibilityGraphQLRequest(client: client)

        XCTAssertEqual(try restRequest.buildURLRequest().url?.path, "/v1/users")
        XCTAssertEqual(try graphQLRequest.buildURLRequest().url?.path, "/graphql")

        let cache = InMemoryResponseCache(capacity: 10)
        let registry = CircuitBreakerRegistry(failureThreshold: 2, resetTimeout: 1)
        let protectedTransport = RouteCircuitBreakingTransport(
            upstream: URLSessionTransport(session: client.session),
            registry: registry
        )
        let cachedTransport = CachingTransport(upstream: protectedTransport, cache: cache)
        _ = cachedTransport

        let routeKey = CircuitBreakerRouteKey.hostAndPath(for: try restRequest.buildURLRequest())
        let breaker = await registry.circuit(for: routeKey)
        try await breaker.allowRequest()
        let snapshots = await registry.snapshots()
        XCTAssertEqual(snapshots[routeKey]?.state, .closed)

        let observer = OSLogNetworkObserver(subsystem: "com.example.compatibility")
        await observer.record(.started(.init(id: "contract", method: .get, url: client.baseURL)))
        let metrics = NetworkMetrics()
        let metricsObserver = NetworkMetricsObserver(metrics: metrics)
        await metricsObserver.record(.finished(.init(id: "contract", method: .get, url: client.baseURL), .init(statusCode: 200, duration: 0.01, error: nil)))
        _ = await metrics.snapshot()
        _ = RequestIDInterceptor()
        _ = RetryPolicy(maxAttempts: 3)
        _ = NetworkConfiguration(timeoutInterval: 15)
        _ = CertificatePinningEvaluator(pinnedCertificates: [:])
        _ = PublicKeyHashPinningEvaluator(pinnedHashes: [:])
        _ = GraphQLResponse<CompatibilityUser>(data: nil, errors: nil)
    }
}

private final class CompatibilityClient: NetworkClient, @unchecked Sendable {
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .ephemeral)
    let interceptors: [any NetworkInterceptor] = []
}

private struct CompatibilityUser: Decodable, Sendable {
    let id: String
}

private struct CompatibilityRESTRequest: RestfulRequest {
    typealias Response = CompatibilityUser

    let client: any NetworkClient
    let path = "/v1/users"
    let method: HTTPMethod = .get
    let queryItems: [URLQueryItem]? = nil
    let body: (any Encodable & Sendable)? = nil
    let contentType: String? = nil
}

private struct CompatibilityGraphQLRequest: GraphQLRequest {
    typealias Response = GraphQLResponse<CompatibilityUser>

    let client: any NetworkClient
    let query = "query CurrentUser { user { id } }"
}
