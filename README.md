# NetworkingKit

[简体中文](README.zh-Hans.md)

NetworkingKit is a lightweight, native Swift networking library for iOS and macOS apps. It supports REST, GraphQL, `async/await`, Combine, Swift 6 concurrency, configurable client defaults, error localization, and request interceptors.

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
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "2.3.6")
]
```

Then add `NetworkingKit` to the target dependencies that use it.

## Quick start

### 1. Create an app client

An app owns its base URL, `URLSession`, transport, interceptors, codec factories, and default configuration in one `NetworkClient` implementation.

```swift
import Foundation
import NetworkingKit

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

actor TokenStore: AccessTokenProviding {
    static let shared = TokenStore()

    func accessToken() async -> String? {
        // Read the current token from secure storage.
        nil
    }

    func refreshAccessToken() async throws -> String? {
        // Use a dedicated refresh endpoint/session and persist the returned token.
        nil
    }
}

final class AppNetworkClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let configuration = AppNetworkConfiguration.production
    private let refreshingAuthentication = RefreshingAuthInterceptor(provider: TokenStore.shared)

    var interceptors: [any NetworkInterceptor] {
        [
            RequestIDInterceptor(),
            AppCommonHeadersInterceptor(),
            refreshingAuthentication,
            LoggingInterceptor(logBodies: false) { print($0) }
        ]
    }

    var authentication: (any AuthenticationRefreshing)? { refreshingAuthentication }
    let observers: [any NetworkObserving] = [AppNetworkObserver()]
    let executionController: (any NetworkExecutionControlling)? = RequestConcurrencyLimiter(maximumConcurrentRequests: 6)

    private init() {
        let sessionConfiguration = URLSessionConfiguration.default
        session = URLSession(configuration: sessionConfiguration)

    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

`NetworkConfiguration` is immutable and scoped to one client. A request can still override `timeoutInterval` when a specific endpoint needs a different timeout. `makeEncoder()` and `makeDecoder()` create a fresh codec per operation, avoiding shared mutable codec configuration. Configure app-wide headers, authentication, request signing, logging, and metrics in `interceptors`; do not add them to `AppRequest`.

### 2. Add an app request protocol

Use an app-level protocol to avoid repeating the client in every request. `NetworkRequest` binds both a concrete `Client` type and a `Response` type. `AppNetworkRequest` directly constrains `Client` to `AppNetworkClient` without erasing it to `any NetworkClient`; each REST or GraphQL request declares only its `Response`. This makes it impossible to accidentally use a request from one backend family with another backend's client. When an app has multiple backend clients, define one equivalent request protocol per client. This pattern works with both structures and classes. The protocol should not own common headers, authentication, or logging because those responsibilities apply to every request and belong to `NetworkInterceptor`.

```swift
protocol AppNetworkRequest: NetworkRequest
where Client == AppNetworkClient {}

extension AppNetworkRequest {
    var client: AppNetworkClient {
        .shared
    }
}
```

### 3. Define a REST request

```swift
struct User: Decodable, Sendable {
    let id: String
    let name: String
}

struct GetUserRequest: AppNetworkRequest, RestfulRequest {
    typealias Response = User
    var path: String { "/users/123" }
    var method: HTTPMethod { .get }

    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

For a JSON request body, return any `Encodable & Sendable` value from `body`. The library automatically applies `application/json` unless a request supplies another `contentType`.

For successful endpoints with no response body, such as `204 No Content`, use `EmptyResponse` as the response type.

```swift
struct DeleteUserRequest: AppNetworkRequest, RestfulRequest {
    typealias Response = EmptyResponse
    var path: String { "/users/123" }
    var method: HTTPMethod { .delete }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

### 4. Define a GraphQL request

GraphQL responses retain both partial `data` and server `errors`.

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
    let email: String
}

struct FetchUserProfileRequest: AppNetworkRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>
    var query: String {
        """
        query {
            user { id name email }
        }
        """
    }
}
```

`GraphQLRequest` supplies `/graphql`, `POST`, and JSON `Accept`/`Content-Type` headers by default. Override them only when a GraphQL server uses a different endpoint or request format.

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

Interceptors run in declaration order on the way out: `adapt(_:)` runs before the configured `NetworkTransport` sends the request. `transform(response:data:)` runs in reverse declaration order on the way back, before HTTP status validation and decoding. It can inspect, validate, or replace the response data. Throwing from either method produces `NetworkError.interceptorFailed`.

### Custom transport

`URLSessionTransport` is the default. Override `transport` for deterministic tests or a custom stack while keeping request definitions unchanged:

```swift
struct StubTransport: NetworkTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (#"{"id":"42","name":"Ada"}"#.data(using: .utf8)!, response)
    }
}

let transport: any NetworkTransport = StubTransport()
```

### Observability and execution controls

Use `OSLogNetworkObserver(subsystem: "com.example.app")` for zero-dependency unified logging. For OpenTelemetry, implement `OpenTelemetryExporting` with your SDK and register `OpenTelemetryNetworkObserver(exporter:)`; NetworkingKit remains SDK-agnostic.

Add `RequestIDInterceptor()` to propagate an `X-Request-ID` value. `NetworkObserving` receives start and finish events for every transport attempt, including status, duration, and a structured `NetworkError` when one occurs. Implement it with an actor to forward data to OSLog, OpenTelemetry, or your telemetry service without blocking requests.

For vendor-neutral aggregate health metrics, attach `NetworkMetricsObserver`. The actor-backed collector reports request counts, transport failures, HTTP status-code distribution, and average attempt duration; snapshot it periodically and export it with your preferred metrics SDK.

```swift
let metrics = NetworkMetrics()
let observers: [any NetworkObserving] = [
    OSLogNetworkObserver(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app"),
    NetworkMetricsObserver(metrics: metrics)
]

let snapshot = await metrics.snapshot()
```

```swift
actor AppNetworkObserver: NetworkObserving {
    func record(_ event: NetworkEvent) async {
        switch event {
        case let .started(context):
            AppLogger.network.info("Started \(context.id)")
        case let .finished(context, outcome):
            AppLogger.network.info("Finished \(context.id), status: \(outcome.statusCode ?? 0)")
        }
    }
}
```

Use `RequestConcurrencyLimiter` as the client’s `executionController` to cap simultaneous transport attempts. Retries and one-time authentication replays each count as an attempt, which prevents failure storms from exhausting device or backend resources.

### Caching, offline mode, and transport security

Wrap the default transport to cache successful `GET` responses. `returnCacheElseLoad` is cache-first; `returnCacheDontLoad` provides deterministic offline behavior and throws `CacheMissError` when no entry exists.

```swift
let cache = InMemoryResponseCache(capacity: 200)
let transport = CachingTransport(
    upstream: URLSessionTransport(session: session),
    cache: cache,
    policy: .returnCacheElseLoad
)
```

For cache survival across launches and standards-based revalidation, use `DiskResponseCache`. Expired entries automatically send `If-None-Match` when an ETag is available; a `304 Not Modified` response reuses the local body and refreshes its TTL.

The cache honors request and response `Cache-Control: no-store`, `no-cache`, and `Expires`; it maintains separate response variants for `Vary` headers and never stores `Vary: *` responses. `304 Not Modified` merges its metadata with the cached response before refreshing TTL. The in-memory cache keeps entries in least-recently-used order.

```swift
let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("NetworkingKitCache")
let cache = DiskResponseCache(directory: directory, maximumSize: 50 * 1_024 * 1_024)
let transport = CachingTransport(upstream: URLSessionTransport(session: session), cache: cache)
```

Call `await cache.statistics()` for its file count and total size, and `await cache.removeAll()` to clear it on logout or when the app needs to reclaim storage. Files are pruned by least-recent access when the configured size limit is exceeded.

Use `CertificatePinningEvaluator` and `ServerTrustSessionDelegate` to pin leaf-certificate DER data per host. Keep at least two pins during certificate rotation, and retain normal system trust evaluation before accepting a pin.

```swift
let evaluator = CertificatePinningEvaluator(pinnedCertificates: [
    "api.example.com": [currentCertificateDER, nextCertificateDER]
])
let delegate = ServerTrustSessionDelegate(evaluator: evaluator)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

For certificate rotation, `PublicKeyHashPinningEvaluator` accepts SHA-256 hashes of the leaf public-key bytes. Keep both the active and backup hashes in `pinnedHashes` before switching certificates.

### Circuit breaker

Wrap a transport with `CircuitBreakingTransport` to stop repeated failures from overwhelming an unhealthy service. It exposes a `CircuitBreakerSnapshot` for lightweight health metrics and admits exactly one half-open recovery probe after `resetTimeout`.

```swift
let transport = CircuitBreakingTransport(
    upstream: URLSessionTransport(session: session),
    circuitBreaker: CircuitBreaker(failureThreshold: 5, resetTimeout: 30)
)
```

Most apps should use `RouteCircuitBreakingTransport`. It gives each method/host/port/path combination its own circuit, so one failed endpoint does not block healthy API routes. Keep caching outside it so cache hits remain available while an upstream route recovers. `CircuitBreakerRegistry.snapshots()` provides route-keyed state for diagnostics and telemetry.

```swift
let registry = CircuitBreakerRegistry(failureThreshold: 5, resetTimeout: 30)
let transport = CachingTransport(
    upstream: RouteCircuitBreakingTransport(
        upstream: URLSessionTransport(session: session),
        registry: registry
    ),
    cache: InMemoryResponseCache(capacity: 200)
)
```

### Built-in interceptors

`AuthInterceptor` adds a bearer token when one is available:

```swift
AuthInterceptor { TokenStore.shared.accessToken }
```

For expiring bearer tokens, use `RefreshingAuthInterceptor` instead. Register the *same instance* in both `interceptors` and `authentication`. On `401`, concurrent requests share one refresh operation and every affected request is replayed at most once. A failed refresh produces `NetworkError.authenticationRefreshFailed`; it never loops indefinitely.

`AccessTokenProviding` should normally be an actor. Perform the refresh through a dedicated endpoint or session so that the refresh operation does not recursively enter the authenticated request pipeline.

`LoggingInterceptor` logs request and response metadata. It redacts `Authorization`, cookies, and API keys by default. Keep `logBodies` disabled in production unless body logging is explicitly safe.

```swift
LoggingInterceptor(
    logBodies: false,
    logger: { message in AppLogger.network.debug("\(message)") }
)
```

### Custom interceptor

This interceptor adds application-wide headers to every request. Register it once on `AppNetworkClient.interceptors`, alongside authentication and logging:

```swift
struct AppCommonHeadersInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        return request
    }
}

let interceptors: [any NetworkInterceptor] = [
    AppCommonHeadersInterceptor(),
    AuthInterceptor { TokenStore.shared.accessToken },
    LoggingInterceptor(logBodies: false)
]
```

The included Demo registers `DemoCommonHeadersInterceptor`, `AuthInterceptor`, and `LoggingInterceptor`, so app-wide behavior is configured on the client rather than repeated in request types.

## Retry behavior

`RetryPolicy` is disabled by default. When enabled, it retries transport errors and HTTP 408, 429, and 5xx responses with capped exponential backoff, jitter, and optional `Retry-After` support. By default, only idempotent methods (`GET`, `HEAD`, `PUT`, `DELETE`, and `OPTIONS`) are retried. Add `POST` explicitly only when the backend supports idempotency keys.

```swift
let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, multiplier: 2)
let idempotentPostPolicy = RetryPolicy(
    maxAttempts: 3,
    retryableMethods: [.get, .head, .put, .delete, .options, .post]
)
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

For app-specific server error decoding or request correlation, use the structured HTTP context rather than parsing a localized message:

```swift
if let networkError = error as? NetworkError,
   let statusCode = networkError.statusCode {
    let requestID = networkError.responseHeaders?["X-Request-ID"]
    let serverBody = networkError.responseBody
    print(statusCode, requestID ?? "", serverBody?.count ?? 0)
}
```

## Demo

Open `Examples/NetworkingKitDemo/NetworkingKitDemo.xcodeproj` and run either `NetworkingKitDemo-iOS` or `NetworkingKitDemo-macOS`. The demo contains REST, GraphQL, app-level configuration, a bilingual error localizer, and both built-in and custom interceptors.

## Development

### Public API compatibility

Every pull request compiles `NetworkingKitAPICompatibilityTests`, a representative third-party integration that imports only the public module surface. The fixture covers client setup, REST, GraphQL, caching, route-scoped circuit breaking, observability, retry configuration, and pinning. Treat changes that break this fixture as source-breaking and document them in a major-version migration guide.

`PerformanceTests` also measures JSON decoding and URL request construction. These are regression signals rather than absolute device-performance targets; use them to investigate meaningful changes in hot-path allocations or execution time.

## License

MIT. See [LICENSE](LICENSE).

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance, and [SECURITY.md](SECURITY.md) for responsible vulnerability reporting.

CI runs debug tests, release builds, and both Demo targets. Tags matching `v*` run the same verification and create a GitHub Release when one does not already exist.
