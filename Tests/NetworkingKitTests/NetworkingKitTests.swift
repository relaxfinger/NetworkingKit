//
//  NetworkingKitTests.swift
//  NetworkingKitTests
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
@testable import NetworkingKit

final class NetworkingKitTests: XCTestCase {
    func testRESTRequestBuildsQueryAndJSONBody() throws {
        let client = makeClient()
        let request = CreateUserRequest(client: client, name: "Ada")

        let urlRequest = try request.buildURLRequest()

        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://example.com/api/users?source=test")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try JSONDecoder().decode(CreateUserBody.self, from: try XCTUnwrap(urlRequest.httpBody)).name, "Ada")
    }

    func testExecuteDecodesSuccessfulResponse() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/users/42")
            return (.init(url: try! XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, #"{"id":"42","name":"Ada"}"#.data(using: .utf8)!)
        }

        let user = try await GetUserRequest(client: client, id: "42").execute()

        XCTAssertEqual(user, User(id: "42", name: "Ada"))
    }

    func testClientInterceptorAppliesCommonHeaders() async throws {
        let client = makeClient(interceptors: [CommonHeadersInterceptor()]) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Platform"), "iOS")
            return (.init(url: try! XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, #"{"id":"42","name":"Ada"}"#.data(using: .utf8)!)
        }

        _ = try await GetUserRequest(client: client, id: "42").execute()
    }

    func testResponseInterceptorTransformsDataBeforeDecoding() async throws {
        let client = makeClient(interceptors: [ResponseEnvelopeInterceptor()]) { request in
            let response = HTTPURLResponse(
                url: try! XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, #"{"payload":{"id":"42","name":"Ada"}}"#.data(using: .utf8)!)
        }

        let user = try await GetUserRequest(client: client, id: "42").execute()

        XCTAssertEqual(user, User(id: "42", name: "Ada"))
    }

    func testObserverReceivesRequestLifecycleAndCorrelationID() async throws {
        let observer = EventRecorder()
        let client = makeClient(observers: [observer]) { request in
            let response = HTTPURLResponse(
                url: try! XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, #"{"id":"42","name":"Ada"}"#.data(using: .utf8)!)
        }

        _ = try await GetUserRequest(client: client, id: "42").execute()
        let events = await observer.events

        guard case let .started(context) = events.first else { return XCTFail("Expected start event") }
        XCTAssertFalse(context.id.isEmpty)
        guard case let .finished(_, outcome) = events.last else { return XCTFail("Expected finish event") }
        XCTAssertEqual(outcome.statusCode, 200)
        XCTAssertNil(outcome.error)
    }

    func testExecuteMapsUnauthorizedResponse() async {
        let client = makeClient { request in
            (.init(url: try! XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: ["X-Request-ID": "trace-1"])!, Data())
        }

        do {
            let _: User = try await GetUserRequest(client: client, id: "42").execute()
            XCTFail("Expected unauthorized error")
        } catch let error as NetworkError {
            guard case let .unauthorized(headers, body) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(headers["X-Request-ID"], "trace-1")
            XCTAssertEqual(body, Data())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConcurrentUnauthorizedRequestsRefreshOnceAndReplay() async throws {
        let credentials = TestCredentialProvider()
        let authentication = RefreshingAuthInterceptor(provider: credentials)
        let client = makeClient(interceptors: [authentication], authentication: authentication) { request in
            let statusCode = request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token" ? 200 : 401
            let response = HTTPURLResponse(
                url: try! XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = statusCode == 200 ? #"{"id":"42","name":"Ada"}"#.data(using: .utf8)! : Data()
            return (response, data)
        }

        async let first = GetUserRequest(client: client, id: "42").execute()
        async let second = GetUserRequest(client: client, id: "43").execute()
        let users = try await [first, second]
        let refreshCount = await credentials.refreshCount

        XCTAssertEqual(users.map(\.name), ["Ada", "Ada"])
        XCTAssertEqual(refreshCount, 1)
    }

    func testGraphQLResponseKeepsDataAndErrors() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let json = #"{"data":{"id":"42","name":"Ada"},"errors":[{"message":"partial result","path":["user",0]}]}"#
            return (.init(url: try! XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, json.data(using: .utf8)!)
        }

        let response = try await UserGraphQLRequest(client: client).execute()

        XCTAssertEqual(response.data, User(id: "42", name: "Ada"))
        XCTAssertEqual(response.errors?.first?.message, "partial result")
        XCTAssertEqual(response.errors?.first?.path, [.string("user"), .number(0)])
    }

    func testRetriesTransientServerError() async throws {
        let counter = AttemptCounter()
        let client = makeClient(retryPolicy: .init(maxAttempts: 2, initialDelay: 0)) { request in
            let attempt = counter.increment()
            let status = attempt == 1 ? 503 : 200
            let data = status == 200 ? #"{"id":"42","name":"Ada"}"#.data(using: .utf8)! : Data()
            return (.init(url: try! XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }

        let user = try await GetUserRequest(client: client, id: "42").execute()

        XCTAssertEqual(user.name, "Ada")
        XCTAssertEqual(counter.value, 2)
    }

    func testDoesNotRetryPostWithoutExplicitPolicy() async {
        let counter = AttemptCounter()
        let client = makeClient(retryPolicy: .init(maxAttempts: 2, initialDelay: 0)) { request in
            _ = counter.increment()
            return (.init(url: try! XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            let _: User = try await CreateUserRequest(client: client, name: "Ada").execute()
            XCTFail("Expected server error")
        } catch let error as NetworkError {
            guard case .http = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(counter.value, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyResponseDecodesEmptyResponseType() async throws {
        let client = makeClient { request in
            (.init(url: try! XCTUnwrap(request.url), statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let response = try await DeleteUserRequest(client: client, id: "42").execute()

        XCTAssertEqual(response, EmptyResponse())
    }

    func testClientConfigurationProvidesDefaultTimeout() throws {
        let expectedTimeout: TimeInterval = 12
        let client = makeClient(configuration: NetworkConfiguration(timeoutInterval: expectedTimeout))
        let request = GetUserRequest(client: client, id: "42")

        XCTAssertEqual(try request.buildURLRequest().timeoutInterval, expectedTimeout)
    }

    func testNetworkErrorUsesConfiguredLocalizer() {
        let configuration = NetworkConfiguration(errorLocalizer: TestNetworkErrorLocalizer())
        let error = NetworkError.unauthorized(headers: [:], body: Data())

        XCTAssertEqual(
            error.localizedDescription(
                using: configuration.errorLocalizer,
                locale: Locale(identifier: "zh-Hans")
            ),
            "登录已过期，请重新登录"
        )
    }

    func testNetworkErrorExposesHTTPContext() {
        let body = #"{"message":"rate limited"}"#.data(using: .utf8)!
        let error = NetworkError.http(statusCode: 429, headers: ["X-Request-ID": "trace-1"], body: body)

        XCTAssertEqual(error.statusCode, 429)
        XCTAssertEqual(error.responseHeaders?["X-Request-ID"], "trace-1")
        XCTAssertEqual(error.responseBody, body)
    }

    private func makeClient(
        configuration: NetworkConfiguration? = nil,
        retryPolicy: RetryPolicy = .none,
        interceptors: [any NetworkInterceptor] = [],
        authentication: (any AuthenticationRefreshing)? = nil,
        observers: [any NetworkObserving] = [],
        handler: @escaping StubTransport.Handler = { request in
        (.init(url: try! XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
    }) -> TestClient {
        return TestClient(
            baseURL: URL(string: "https://example.com/api")!,
            transport: StubTransport(handler: handler),
            interceptors: interceptors,
            authentication: authentication,
            observers: observers,
            configuration: configuration ?? NetworkConfiguration(retryPolicy: retryPolicy)
        )
    }
}

private struct User: Codable, Equatable, Sendable { let id: String; let name: String }
private struct CreateUserBody: Codable, Sendable { let name: String }

private struct TestNetworkErrorLocalizer: NetworkErrorLocalizing {
    func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .unauthorized: return "登录已过期，请重新登录"
        default: return "网络请求失败"
        }
    }
}

private struct CommonHeadersInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        return request
    }
}

private struct ResponseEnvelopeInterceptor: NetworkInterceptor {
    func transform(response: URLResponse, data: Data) async throws -> Data {
        try JSONDecoder().decode(ResponseEnvelope.self, from: data).payload
    }
}

private struct ResponseEnvelope: Decodable {
    let payload: Data

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decode(User.self, forKey: .payload)
        self.payload = try JSONEncoder().encode(payload)
    }

    private enum CodingKeys: String, CodingKey { case payload }
}

private struct GetUserRequest: RestfulRequest {
    typealias Response = User
    let client: any NetworkClient
    let id: String
    var path: String { "users/\(id)" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

private struct CreateUserRequest: RestfulRequest {
    typealias Response = User
    let client: any NetworkClient
    let name: String
    var path: String { "users" }
    var method: HTTPMethod { .post }
    var queryItems: [URLQueryItem]? { [.init(name: "source", value: "test")] }
    var body: (any Encodable & Sendable)? { CreateUserBody(name: name) }
    var contentType: String? { nil }
}

private struct DeleteUserRequest: RestfulRequest {
    typealias Response = EmptyResponse
    let client: any NetworkClient
    let id: String
    var path: String { "users/\(id)" }
    var method: HTTPMethod { .delete }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

private struct UserGraphQLRequest: GraphQLRequest {
    typealias Response = GraphQLResponse<User>
    let client: any NetworkClient
    let query = "query User { user { id name } }"
}

private final class TestClient: NetworkClient, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession
    let transport: any NetworkTransport
    let interceptors: [any NetworkInterceptor]
    let authentication: (any AuthenticationRefreshing)?
    let observers: [any NetworkObserving]
    let configuration: NetworkConfiguration
    init(
        baseURL: URL,
        transport: any NetworkTransport,
        interceptors: [any NetworkInterceptor],
        authentication: (any AuthenticationRefreshing)?,
        observers: [any NetworkObserving],
        configuration: NetworkConfiguration
    ) {
        self.baseURL = baseURL
        self.session = .shared
        self.transport = transport
        self.interceptors = interceptors
        self.authentication = authentication
        self.observers = observers
        self.configuration = configuration
    }
}

private actor EventRecorder: NetworkObserving {
    private(set) var events: [NetworkEvent] = []

    func record(_ event: NetworkEvent) async {
        events.append(event)
    }
}

private actor TestCredentialProvider: AccessTokenProviding {
    private var token = "expired-token"
    private(set) var refreshCount = 0

    func accessToken() async -> String? { token }

    func refreshAccessToken() async throws -> String? {
        refreshCount += 1
        try await Task.sleep(nanoseconds: 10_000_000)
        token = "fresh-token"
        return token
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; attempts += 1; return attempts }
    var value: Int { lock.lock(); defer { lock.unlock() }; return attempts }
}

private struct StubTransport: NetworkTransport {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    let handler: Handler

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (response, data) = handler(request)
        return (data, response)
    }
}
