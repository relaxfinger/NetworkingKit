# 认证与 Token 刷新

[English](Authentication.md) · [文档索引](README.zh-Hans.md)

认证属于后端共享行为，应配置在 Client，而不是每个 Request。Token 只需读取时使用 `AuthInterceptor`；Bearer Token 会过期时使用 `RefreshingAuthInterceptor`。

## 静态或外部提前刷新的 Token

当其他组件已经在 API 调用前刷新凭证时，使用 `AuthInterceptor`：

```swift
let authentication = AuthInterceptor(tokenProvider: {
    KeychainStore.shared.accessToken
})

var interceptors: [any NetworkInterceptor] { [authentication] }
```

没有 Token 时闭包应返回 `nil`，请求不会携带 `Authorization` Header。

## 会过期的 Bearer Token

使用 actor 实现 `AccessTokenProviding`。多个并发请求读取 Token 时，actor 能保护可变凭证。刷新必须走独立接口或 Session，避免刷新请求再次进入需要认证的 Client。

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

创建一个 `RefreshingAuthInterceptor` 实例，并将**同一个对象**注册两次：

```swift
final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .default)

    private let refreshingAuth = RefreshingAuthInterceptor(provider: TokenStore.shared)

    var interceptors: [any NetworkInterceptor] {
        [RequestIDInterceptor(), refreshingAuth]
    }

    var authentication: (any AuthenticationRefreshing)? { refreshingAuth }
}
```

当请求收到 `401 Unauthorized`，并发请求会共享一次刷新操作。刷新成功后，每个请求至多重放一次；刷新失败转换为 `NetworkError.authenticationRefreshFailed`。这避免重复刷新流量和无限重试。

## 产品与安全规则

- Access Token 与 Refresh Token 保存到安全存储，不要放入响应缓存或日志。
- 登出时清理 Token 和用户相关 HTTP 缓存。
- 刷新请求必须绕开已认证请求链路。
- 不是每个 `401` 都适合刷新；后端应一致地用它表示过期或无效凭证。
- 覆盖并发 `401`、刷新失败、取消以及重放后再次 `401` 的测试。
