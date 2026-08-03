# Client Profile

[English](ClientProfiles.md) · [文档索引](README.zh-Hans.md)

一个 `NetworkClient` 对应一个 Base URL。同一地址下的请求族需要不同公共 Header、认证、超时或重试行为时，由同一个 Client 暴露多个 `NetworkClientProfile`。

Profile 只包含请求执行链行为：

- 通过 interceptor 统一处理请求与响应；
- 收到 `401` 后可选的凭证刷新与单次重放；
- 通过 `NetworkConfiguration` 配置超时、重试和错误本地化。

Base URL、Session、Transport、编解码器、Observer、并发控制和传输信任策略仍属于整个 Client。

## 在 Client 中定义 Profile

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

依赖可在初始化阶段取得时应优先使用存储属性。上例使用 `lazy`，只是为了在简短示例中引用另一个实例属性。

## 由请求族选择 Profile

Request 默认使用 `client.defaultProfile`。需要另一套行为时，在 App 级请求协议统一选择，具体 endpoint 不重复配置。

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

`clientProfile` 是执行元数据，不是 endpoint 参数。不要通过可变状态切换 Client 的当前 Profile；并发请求可能同时需要不同 Profile。

## 判断边界

Base URL、Session、Transport、编解码器和信任策略相同，只有共享请求行为不同时，使用另一个 Profile。Base URL 不同时，使用另一个 Client。只有单个 endpoint 特殊时，可直接覆盖 `headers` 或 `timeoutInterval`，无需新增 Profile。

## 从 2.4 迁移

NetworkingKit 2.5 将 Profile 纳入 Client 核心契约。把原来 Client 顶层的 `interceptors`、`authentication` 和 `configuration` 移入 `defaultProfile`：

```swift
let defaultProfile = NetworkClientProfile(
    interceptors: [commonHeaders, refreshingAuth],
    authentication: refreshingAuth,
    configuration: NetworkConfiguration(timeoutInterval: 15)
)
```

Request 仍然调用 `execute()` 并自动使用默认 Profile；只有需要不同共享行为的请求族才添加 `clientProfile`。
