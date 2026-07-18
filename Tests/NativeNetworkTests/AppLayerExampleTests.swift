//
//  AppLayerExampleTests.swift
//  NativeNetworkTests
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
@testable import NativeNetwork

final class AppLayerExampleTests: XCTestCase {
    func testClassBasedAppRequestPatternBuildsRESTAndGraphQLRequests() throws {
        let rest = try GetUserRequest().buildURLRequest()
        XCTAssertEqual(rest.url?.absoluteString, "https://api.example.com/users/123")

        let graphQL = try FetchUserProfileRequest().buildURLRequest()
        XCTAssertEqual(graphQL.url?.absoluteString, "https://api.example.com/graphql")
        XCTAssertEqual(graphQL.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}

private final class AppNetworkClient: NetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession = .shared
    let interceptors: [any NetworkInterceptor] = []
    private init() {}
}

private class AppRequest<T: Decodable & Sendable>: NetworkRequest, @unchecked Sendable {
    typealias Response = T
    let client: any NetworkClient = AppNetworkClient.shared
    var path: String { "" }
    var method: HTTPMethod { .get }
    var headers: [String: String]? { nil }
}

private struct User: Codable, Sendable { let id: String }
private struct UserProfile: Codable, Sendable { let id: String }

private final class GetUserRequest: AppRequest<User>, RestfulRequest, @unchecked Sendable {
    override var path: String { "/users/123" }
    override var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

private final class FetchUserProfileRequest: AppRequest<GraphQLResponse<UserProfile>>, GraphQLRequest, @unchecked Sendable {
    override var path: String { "/graphql" }
    override var method: HTTPMethod { .post }
    var query: String { "query { user { id } }" }
    override var headers: [String: String]? { ["Accept": "application/json", "Content-Type": "application/json"] }
}
