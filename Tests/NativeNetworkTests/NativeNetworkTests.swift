import Foundation
import XCTest
@testable import NativeNetwork

final class NativeNetworkTests: XCTestCase {
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

    private func makeClient(retryPolicy: RetryPolicy = .none, handler: @escaping URLProtocolStub.Handler = { request in
        (.init(url: try! XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
    }) -> TestClient {
        URLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return TestClient(baseURL: URL(string: "https://example.com/api")!, session: URLSession(configuration: configuration), retryPolicy: retryPolicy)
    }
}

private struct User: Codable, Equatable, Sendable { let id: String; let name: String }
private struct CreateUserBody: Codable, Sendable { let name: String }

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

private struct UserGraphQLRequest: GraphQLRequest {
    typealias Response = GraphQLResponse<User>
    let client: any NetworkClient
    let query = "query User { user { id name } }"
}

private final class TestClient: NetworkClient, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession
    let interceptors: [any NetworkInterceptor] = []
    let retryPolicy: RetryPolicy
    init(baseURL: URL, session: URLSession, retryPolicy: RetryPolicy) { self.baseURL = baseURL; self.session = session; self.retryPolicy = retryPolicy }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; attempts += 1; return attempts }
    var value: Int { lock.lock(); defer { lock.unlock() }; return attempts }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
