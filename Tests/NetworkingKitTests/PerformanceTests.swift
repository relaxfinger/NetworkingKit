//
//  PerformanceTests.swift
//  NetworkingKitTests
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
@testable import NetworkingKit

final class PerformanceTests: XCTestCase {
    func testJSONDecoderPerformance() throws {
        let data = Data(#"{"id":"42","name":"Ada"}"#.utf8)
        measure {
            _ = try? JSONDecoder().decode(BenchmarkUser.self, from: data)
        }
    }

    func testURLRequestConstructionPerformance() throws {
        let client = BenchmarkClient()
        let request = BenchmarkRequest(client: client)

        measure {
            _ = try? request.buildURLRequest()
        }
    }
}

private struct BenchmarkUser: Codable, Sendable { let id: String; let name: String }

private final class BenchmarkClient: NetworkClient, @unchecked Sendable {
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .ephemeral)
    let interceptors: [any NetworkInterceptor] = []
}

private struct BenchmarkRequest: RestfulRequest {
    typealias Response = BenchmarkUser

    let client: BenchmarkClient
    let path = "/v1/users"
    let method: HTTPMethod = .post
    let queryItems: [URLQueryItem]? = [.init(name: "page", value: "1")]
    let body: (any Encodable & Sendable)? = BenchmarkUser(id: "42", name: "Ada")
    let contentType: String? = nil
}
