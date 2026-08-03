# Client profiles

[简体中文](ClientProfiles.zh-Hans.md) · [Documentation index](README.md)

A `NetworkClient` represents one base URL. When request families on that URL need different shared headers, authentication, timeout, or retry behavior, expose multiple `NetworkClientProfile` values from the same client.

Profiles contain only request-pipeline behavior:

- interceptors for shared request and response processing;
- an optional credential refresher for one replay after `401`;
- `NetworkConfiguration` for timeout, retry, and error localization.

The base URL, session, transport, codecs, observers, concurrency control, and trust policy remain client-wide.

## Define profiles on the client

```swift
final class APIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = APIClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .default)

    private let bearerAuth = RefreshingAuthInterceptor(provider: TokenStore.shared)

    lazy var defaultProfile = NetworkClientProfile(
        interceptors: [CommonHeadersInterceptor(), bearerAuth],
        authentication: bearerAuth,
        configuration: NetworkConfiguration(
            timeoutInterval: 15,
            retryPolicy: RetryPolicy(maxAttempts: 3)
        )
    )

    let authProfile = NetworkClientProfile(
        interceptors: [APIKeyInterceptor()],
        configuration: NetworkConfiguration(timeoutInterval: 10)
    )
}
```

Use a stored profile when its dependencies are available during initialization. The `lazy` default above only keeps the example compact while referring to another instance property.

## Select a profile by request family

Every request uses `client.defaultProfile` unless it selects another profile. Put that selection on an App-level request protocol so concrete endpoints do not repeat it.

```swift
protocol APIRequest: NetworkRequest where Client == APIClient {}

extension APIRequest {
    var client: APIClient { .shared }
}

protocol AuthRequest: APIRequest {}

extension AuthRequest {
    var clientProfile: NetworkClientProfile { client.authProfile }
}

struct SignInRequest: AuthRequest, RestfulRequest {
    typealias Response = Session
    var path: String { "/auth/token" }
    var method: HTTPMethod { .post }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { SignInBody() }
    var contentType: String? { nil }
}
```

`clientProfile` is execution metadata, not an endpoint parameter. Do not switch a client's current profile through mutable state: concurrent requests may need different profiles at the same time.

## Choose the boundary

Use another profile when the base URL, session, transport, codecs, and trust policy remain the same but shared request behavior differs. Use another client when the base URL differs. A single endpoint exception can still override `headers` or `timeoutInterval` directly without creating a new profile.

## Migrate from 2.4

NetworkingKit 2.5 makes profiles part of the core client contract. Move the previous client-level `interceptors`, `authentication`, and `configuration` into `defaultProfile`:

```swift
let defaultProfile = NetworkClientProfile(
    interceptors: [commonHeaders, refreshingAuth],
    authentication: refreshingAuth,
    configuration: NetworkConfiguration(timeoutInterval: 15)
)
```

Requests continue to call `execute()` and automatically use that default. Only request families that need different behavior add `clientProfile`.
