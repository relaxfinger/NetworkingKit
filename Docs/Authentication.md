# Authentication and token refresh

[简体中文](Authentication.zh-Hans.md) · [Documentation index](README.md)

Authentication is shared request behavior, so it belongs in a client profile, not in every request. NetworkingKit provides `AuthInterceptor` for a token that is simply read, and `RefreshingAuthInterceptor` for expiring bearer tokens.

## Static or externally refreshed token

Use `AuthInterceptor` when another component refreshes credentials before API calls:

```swift
let authentication = AuthInterceptor(tokenProvider: {
    KeychainStore.shared.accessToken
})

let defaultProfile = NetworkClientProfile(interceptors: [authentication])
```

The closure should return `nil` when no token exists; the request then proceeds without an `Authorization` header.

## Expiring bearer token

Implement `AccessTokenProviding` with an actor. The actor protects mutable credentials when many concurrent requests ask for a token at once. Refresh through a dedicated endpoint or session so the refresh operation does not recursively enter the authenticated client.

```swift
actor TokenStore: AccessTokenProviding {
    static let shared = TokenStore()

    func accessToken() async -> String? {
        // Read the current token from secure storage.
        nil
    }

    func refreshAccessToken() async throws -> String? {
        // Call a dedicated refresh endpoint, persist the new token, and return it.
        nil
    }
}
```

Create one `RefreshingAuthInterceptor` instance and register that same object twice:

```swift
final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .default)

    private let refreshingAuth = RefreshingAuthInterceptor(provider: TokenStore.shared)

    lazy var defaultProfile = NetworkClientProfile(
        interceptors: [RequestIDInterceptor(), refreshingAuth],
        authentication: refreshingAuth
    )
}
```

When an attempt receives `401 Unauthorized`, concurrent requests share one refresh operation. A request is replayed at most once after a successful refresh; failed refreshes become `NetworkError.authenticationRefreshFailed`. This prevents duplicate refresh traffic and infinite retry loops.

An authentication or token-refresh endpoint on the same base URL should select a profile without bearer refresh. This prevents the refresh call from recursively entering the authenticated request path. See [Client profiles](ClientProfiles.md).

## Product and security rules

- Store access and refresh tokens in secure storage, not in a response cache or logs.
- Clear tokens and user-scoped HTTP cache on logout.
- Keep refresh requests outside the authenticated request path.
- Do not treat every `401` as refreshable: the backend must use it consistently for expired/invalid credentials.
- Test simultaneous `401` responses, refresh failure, cancellation, and a second `401` after replay.
