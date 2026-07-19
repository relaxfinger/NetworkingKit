# Getting started

[简体中文](GettingStarted.zh-Hans.md) · [Documentation index](README.md)

This guide creates the smallest maintainable networking layer: a client for one backend, an App-level request protocol, REST and GraphQL requests, and two ways to execute them.

## 1. Model backend boundaries

Create one `NetworkClient` type per genuinely different backend service. Account, content, and payments may need different base URLs, credentials, session configuration, or security policy. Production, staging, and test are configurations of the same backend client, not different request families.

```swift
import Foundation
import NetworkingKit

enum AccountEnvironment {
    case production
    case staging

    var baseURL: URL {
        switch self {
        case .production: URL(string: "https://api.example.com")!
        case .staging: URL(string: "https://staging-api.example.com")!
        }
    }
}

final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient(environment: .production)

    let baseURL: URL
    let session: URLSession
    let configuration: NetworkConfiguration

    init(environment: AccountEnvironment) {
        baseURL = environment.baseURL
        session = URLSession(configuration: .default)
        configuration = NetworkConfiguration(
            timeoutInterval: 15,
            retryPolicy: RetryPolicy(maxAttempts: 3)
        )
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

`SharedNetworkClient` is useful when normal App requests use one shared instance. A client can instead conform only to `NetworkClient` and be injected into requests when tests or a feature need separate instances.

## 2. Bind an App request protocol to a concrete client

`NetworkRequest` has two associated types: `Client` identifies the backend configuration and `Response` identifies decoded data. Bind the client once with an App protocol; each business request supplies only its response type.

```swift
protocol AccountRequest: NetworkRequest where Client == AccountAPIClient {}

extension AccountRequest {
    var client: AccountAPIClient { .shared }
}
```

For a second backend, define another client and another request protocol. This is compile-time protection against sending an account endpoint through a content client.

## 3. Define REST requests

`RestfulRequest` adds `path`, `method`, query items, a body, and content type. Keep endpoint-specific information here; do not add common headers or token code.

```swift
struct User: Codable, Sendable {
    let id: String
    let name: String
}

struct GetUserRequest: AccountRequest, RestfulRequest {
    typealias Response = User

    let id: String
    var path: String { "/v1/users/\(id)" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { [URLQueryItem(name: "include", value: "roles")] }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

struct UpdateUserBody: Codable, Sendable { let name: String }

struct UpdateUserRequest: AccountRequest, RestfulRequest {
    typealias Response = User

    let id: String
    let name: String
    var path: String { "/v1/users/\(id)" }
    var method: HTTPMethod { .put }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { UpdateUserBody(name: name) }
    var contentType: String? { nil } // Defaults to application/json for a JSON body.
}
```

Use `EmptyResponse` for successful endpoints that intentionally return no body, such as `204 No Content`.

## 4. Define GraphQL requests

`GraphQLRequest` provides `/graphql`, `POST`, and JSON request headers. Override those defaults only when the server is different.

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
    let email: String
}

struct FetchProfileRequest: AccountRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>

    let id: String
    var query: String {
        "query Profile($id: ID!) { user(id: $id) { id name email } }"
    }
    var variables: [String: AnyEncodable]? {
        ["id": AnyEncodable(id)]
    }
    var operationName: String? { "Profile" }
}
```

GraphQL may return usable `data` and server `errors` together. Treat `errors` as product-level information rather than assuming any HTTP-success response means the operation succeeded completely.

## 5. Execute a request

Use Swift Concurrency for new code:

```swift
let user = try await GetUserRequest(id: "42").execute()

let graphQL = try await FetchProfileRequest(id: "42").execute()
let profile = graphQL.data
let serverErrors = graphQL.errors
```

For a screen that already owns Combine cancellation, use the publisher form. Work starts upon subscription and cancellation cancels the underlying request.

```swift
GetUserRequest(id: "42")
    .executePublisher()
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { completion in print(completion) },
        receiveValue: { user in print(user.name) }
    )
    .store(in: &cancellables)
```

## Next steps

- Put common headers and response-envelope handling in [Interceptors](Interceptors.md).
- Add bearer credentials through [Authentication](Authentication.md).
- Use [Caching](Caching.md) before implementing an offline screen.
- Configure [Reliability](Reliability.md) and [Observability](Observability.md) for production operations.
