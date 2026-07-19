//
//  AppLayerExampleTests.swift
//  NetworkingKitTests
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
@testable import NetworkingKit

final class AppLayerExampleTests: XCTestCase {
    func testProtocolBasedAppRequestPatternBuildsRESTAndGraphQLRequests() throws {
        assertAccountClient(GetUserRequest())
        assertAccountClient(FetchUserProfileRequest())

        let rest = try GetUserRequest().buildURLRequest()
        XCTAssertEqual(rest.url?.absoluteString, "https://api.example.com/users/123")

        let graphQL = try FetchUserProfileRequest().buildURLRequest()
        XCTAssertEqual(graphQL.url?.absoluteString, "https://api.example.com/graphql")
        XCTAssertEqual(graphQL.httpMethod, HTTPMethod.post.rawValue)
        XCTAssertEqual(graphQL.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(graphQL.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}

private func assertAccountClient<Request: NetworkRequest>(_ request: Request) where Request.Client == AppNetworkClient {}

private final class AppNetworkClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession = .shared
    let interceptors: [any NetworkInterceptor] = []
    private init() {}
}

private protocol AppNetworkRequest: NetworkRequest where Client == AppNetworkClient {}

private extension AppNetworkRequest {
    var client: AppNetworkClient { .shared }
}

private struct User: Codable, Sendable { let id: String }
private struct UserProfile: Codable, Sendable { let id: String }

private struct GetUserRequest: AppNetworkRequest, RestfulRequest {
    typealias Response = User
    var path: String { "/users/123" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

private struct FetchUserProfileRequest: AppNetworkRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>
    var query: String { "query { user { id } }" }
}
