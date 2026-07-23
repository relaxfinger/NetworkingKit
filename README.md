# NetworkingKit

[简体中文](README.zh-Hans.md) · [Documentation](Docs/README.md)

NetworkingKit is a native Swift networking library for iOS, macOS, tvOS, and watchOS. It provides typed REST and GraphQL requests, Swift Concurrency, Combine, HTTP caching, authentication, retries, observability, and transport security without third-party dependencies.

## Highlights

- Typed REST and GraphQL requests with `async/await` and Combine.
- Client-scoped configuration for timeouts, retries, codecs, and localized errors.
- Interceptors for headers, signing, authentication, logging, response envelopes, and test behavior.
- HTTP caching with memory or disk storage, cache policies, ETag revalidation, `304`, `Vary`, and offline reads.
- Token refresh coordination, request concurrency limits, and route-scoped circuit breakers.
- OSLog, OpenTelemetry bridge points, metrics, request IDs, and certificate/public-key pinning.

## Requirements

- iOS 17+
- macOS 14+
- tvOS 17+
- watchOS 10+
- Swift 6.0+

## Installation

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/relaxfinger/NetworkingKit.git
```

Or add the package manifest dependency:

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "2.4.0")
]
```

Add `NetworkingKit` to the target that defines requests or calls APIs.

## Quick start

### 1. Create a client for one backend

One client owns the base URL, session, defaults, and shared request behavior for one backend. An App can define more than one client when it communicates with genuinely different backend services.

```swift
import Foundation
import NetworkingKit

final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let configuration = NetworkConfiguration(
        timeoutInterval: 15,
        retryPolicy: RetryPolicy(maxAttempts: 3)
    )

    private init() {
        session = URLSession(configuration: .default)
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

### 2. Bind requests to that client

The App-level protocol gives every request for this backend the same concrete client. It does not contain headers, authentication, logging, or cache policy; those belong on the client through interceptors and transports.

```swift
protocol AccountRequest: NetworkRequest where Client == AccountAPIClient {}

extension AccountRequest {
    var client: AccountAPIClient { .shared }
}
```

### 3. Define and execute a REST request

```swift
struct User: Decodable, Sendable {
    let id: String
    let name: String
}

struct GetUserRequest: AccountRequest, RestfulRequest {
    typealias Response = User

    var path: String { "/v1/users/123" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

let user = try await GetUserRequest().execute()
```

`GraphQLRequest` provides `/graphql`, `POST`, and JSON headers by default:

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let email: String
}

struct FetchProfileRequest: AccountRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>
    var query: String { "query { user { id email } }" }
}

let response = try await FetchProfileRequest().execute()
let profile = response.data
let errors = response.errors
```

For a Combine screen, call `executePublisher()` on the same request.

## Documentation

The README is intentionally the shortest path to a first request. Use the detailed, bilingual documentation when building a production client:

| Topic | English | 简体中文 |
| --- | --- | --- |
| Documentation index | [Docs](Docs/README.md) | [文档索引](Docs/README.zh-Hans.md) |
| Client, requests, REST, GraphQL, and Combine | [Getting started](Docs/GettingStarted.md) | [快速入门](Docs/GettingStarted.zh-Hans.md) |
| Memory/disk cache, HTTP semantics, offline mode | [Caching](Docs/Caching.md) | [缓存](Docs/Caching.zh-Hans.md) |
| Shared request/response processing | [Interceptors](Docs/Interceptors.md) | [拦截器](Docs/Interceptors.zh-Hans.md) |
| Bearer tokens and refresh coordination | [Authentication](Docs/Authentication.md) | [认证](Docs/Authentication.zh-Hans.md) |
| Retry, concurrency limits, circuit breakers | [Reliability](Docs/Reliability.md) | [稳定性](Docs/Reliability.zh-Hans.md) |
| Logs, tracing, and metrics | [Observability](Docs/Observability.md) | [可观测性](Docs/Observability.zh-Hans.md) |
| Stable errors and localized UI messages | [Errors](Docs/Errors.md) | [错误与本地化](Docs/Errors.zh-Hans.md) |
| Certificate and public-key pinning | [Security](Docs/Security.md) | [传输安全](Docs/Security.zh-Hans.md) |

## Demo

[`Examples/NetworkingKitDemo`](Examples/NetworkingKitDemo) is a SwiftUI iOS and macOS app that demonstrates REST, GraphQL, interceptors, token refresh wiring, disk caching, a route circuit breaker, concurrency limiting, and localized errors.

## Development

Run the package tests with:

```bash
swift test
```

The public API compatibility fixture is compiled in CI to catch source-breaking changes from a third-party integration perspective.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report security vulnerabilities privately using the contact method in [SECURITY.md](SECURITY.md).

## License

NetworkingKit is released under the [MIT License](LICENSE).
