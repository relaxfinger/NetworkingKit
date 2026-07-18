# NativeNetwork

[简体中文](README.zh-Hans.md)

NativeNetwork is a lightweight, native Swift networking library for iOS and macOS apps. It supports REST, GraphQL, `async/await`, Combine, Swift 6 concurrency, configurable client defaults, error localization, and request interceptors.

## Features

- No third-party dependencies; Foundation and Combine only.
- REST and GraphQL requests with a small protocol-based API.
- `async/await` and Combine APIs.
- Swift 6 concurrency support with `Sendable`-aware public APIs.
- Per-client configuration for timeouts, retries, and localized error messages.
- Built-in `AuthInterceptor` and privacy-conscious `LoggingInterceptor`.
- Custom request/response interceptors for cross-cutting application behavior.

## Requirements

- iOS 17+
- macOS 14+
- tvOS 17+
- watchOS 10+
- Swift 6.0+

## Installation

### Swift Package Manager

Add the package in Xcode through **File > Add Package Dependencies**, or declare it in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "1.0.0")
]
```

Then add `NativeNetwork` to the target dependencies that use it.

## Quick start

### 1. Create an app client

An app owns its base URL, `URLSession`, interceptors, decoders, and default configuration in one `NetworkClient` implementation.

```swift
import Foundation
import NativeNetwork

enum AppNetworkConfiguration {
    static let production = NetworkConfiguration(
        timeoutInterval: 15,
        retryPolicy: RetryPolicy(maxAttempts: 3),
        errorLocalizer: AppNetworkErrorLocalizer()
    )

    static let testing = NetworkConfiguration(
        timeoutInterval: 3,
        retryPolicy: .none,
        errorLocalizer: AppNetworkErrorLocalizer()
    )
}

final class AppNetworkClient: NetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let decoder: JSONDecoder
    let configuration = AppNetworkConfiguration.production
    let interceptors: [any NetworkInterceptor] = [
        AuthInterceptor { TokenStore.shared.accessToken },
        LoggingInterceptor(logBodies: false) { print($0) }
    ]

    private init() {
        let sessionConfiguration = URLSessionConfiguration.default
        session = URLSession(configuration: sessionConfiguration)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
}
```

`NetworkConfiguration` is immutable and scoped to one client. A request can still override `timeoutInterval` when a specific endpoint needs a different timeout.

### 2. Add an app request base class

Use a base class to avoid repeating the client in every request. Requests inheriting from a class must also be classes; Swift structures cannot inherit from classes.

```swift
class AppRequest<T: Decodable & Sendable>: NetworkRequest, @unchecked Sendable {
    typealias Response = T
    let client: any NetworkClient = AppNetworkClient.shared

    var path: String { "" }
    var method: HTTPMethod { .get }
    var headers: [String: String]? { nil }
}
```

### 3. Define a REST request

```swift
struct User: Decodable, Sendable {
    let id: String
    let name: String
}

final class GetUserRequest: AppRequest<User>, RestfulRequest, @unchecked Sendable {
    override var path: String { "/users/123" }
    override var method: HTTPMethod { .get }

    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

For a JSON request body, return any `Encodable & Sendable` value from `body`. The library automatically applies `application/json` unless a request supplies another `contentType`.

### 4. Define a GraphQL request

GraphQL responses retain both partial `data` and server `errors`.

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
    let email: String
}

final class FetchUserProfileRequest: AppRequest<GraphQLResponse<UserProfile>>, GraphQLRequest, @unchecked Sendable {
    override var path: String { "/graphql" }
    override var method: HTTPMethod { .post }
    override var headers: [String: String]? {
        ["Accept": "application/json", "Content-Type": "application/json"]
    }

    var query: String {
        """
        query {
            user { id name email }
        }
        """
    }
}
```

`AppRequest` already provides `path`, `method`, and `headers`, so GraphQL requests explicitly override these values to preserve the GraphQL defaults.

### 5. Execute requests

```swift
let user = try await GetUserRequest().execute()

let profileResponse = try await FetchUserProfileRequest().execute()
let profile = profileResponse.data
let graphQLErrors = profileResponse.errors
```

The Combine API starts work only when subscribed to and cancels the underlying task when the subscription is cancelled.

```swift
GetUserRequest()
    .executePublisher()
    .sink(
        receiveCompletion: { completion in print(completion) },
        receiveValue: { user in print(user.name) }
    )
    .store(in: &cancellables)
```

## Network interceptors

`NetworkInterceptor` handles behavior that should apply consistently across requests: authentication, headers, request signing, logging, response observation, metrics, and test stubs.

Interceptors run in declaration order. `adapt(_:)` runs before `URLSession` sends the request. `intercept(response:data:)` runs after a response is received and before HTTP status validation and decoding. Throwing from either method produces `NetworkError.interceptorFailed`.

### Built-in interceptors

`AuthInterceptor` adds a bearer token when one is available:

```swift
AuthInterceptor { TokenStore.shared.accessToken }
```

`LoggingInterceptor` logs request and response metadata. It redacts `Authorization`, cookies, and API keys by default. Keep `logBodies` disabled in production unless body logging is explicitly safe.

```swift
LoggingInterceptor(
    logBodies: false,
    logger: { message in AppLogger.network.debug("\(message)") }
)
```

### Custom interceptor

This interceptor adds an application header to every request:

```swift
struct ClientHeaderInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        return request
    }
}

let interceptors: [any NetworkInterceptor] = [
    ClientHeaderInterceptor(),
    AuthInterceptor { TokenStore.shared.accessToken },
    LoggingInterceptor(logBodies: false)
]
```

The included Demo registers both `DemoRequestHeaderInterceptor` and `LoggingInterceptor`, so the behavior is visible in the Xcode console while requests run.

## Retry behavior

`RetryPolicy` is disabled by default. When enabled, it retries transport errors and HTTP 408, 429, and 5xx responses with exponential backoff. Only retry non-idempotent requests when your backend supports idempotency keys.

```swift
let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, multiplier: 2)
```

## Localized errors

`NetworkError` is a stable error model. Apps choose display text by injecting `NetworkErrorLocalizing` into `NetworkConfiguration`.

```swift
struct AppNetworkErrorLocalizer: NetworkErrorLocalizing {
    func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .unauthorized:
            return String(localized: "network.error.unauthorized", bundle: .main, locale: locale)
        case let .http(statusCode, _, _):
            return String(
                format: String(localized: "network.error.http_status", bundle: .main, locale: locale),
                statusCode
            )
        default:
            return String(localized: "network.error.generic", bundle: .main, locale: locale)
        }
    }
}

let message = networkError.localizedDescription(
    using: AppNetworkClient.shared.configuration.errorLocalizer,
    locale: .current
)
```

## Demo

Open `Examples/NativeNetworkDemo/NativeNetworkDemo.xcodeproj` and run either `NativeNetworkDemo-iOS` or `NativeNetworkDemo-macOS`. The demo contains REST, GraphQL, app-level configuration, a bilingual error localizer, and both built-in and custom interceptors.

## License

MIT. See [LICENSE](LICENSE).
