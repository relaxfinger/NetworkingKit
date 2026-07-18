# NativeNetwork

轻量级、纯原生 Swift 网络层，同时支持 **RESTful** 和 **GraphQL**。

- 零第三方依赖（仅使用 Foundation + Combine）
- 支持 `async/await` 和 Combine
- 协议驱动，易于继承和扩展
- 内置 Interceptor 机制（Auth、Logging 等）
- Swift 6 strict concurrency（Sendable、Actor 友好）
- 可配置 JSON 编解码、退避重试与默认脱敏日志

**平台要求：iOS 17+、macOS 14+、tvOS 15+、watchOS 8+。**

## 安装

### Swift Package Manager

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "1.0.0")
]
```

或在 Xcode 中：`File` → `Add Package Dependencies...`

## 快速开始

## iOS 与 macOS Demo

仓库的 `Examples/NativeNetworkDemo/NativeNetworkDemo.xcodeproj` 含两个原生 SwiftUI App scheme：`NativeNetworkDemo-iOS` 与 `NativeNetworkDemo-macOS`。选择对应 scheme 并在 Xcode 中运行，即可查看 REST 与 GraphQL 调用。

示例使用 JSONPlaceholder 与 Rick and Morty GraphQL API，仅用于学习和本地验证；生产应用应使用自己的后端地址、认证与日志策略。

### 1. 实现自己的 NetworkClient

```swift
final class AppNetworkClient: NetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()
    
    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let interceptors: [any NetworkInterceptor] = []
    let decoder: JSONDecoder
    let configuration = NetworkConfiguration(
        timeoutInterval: 15,
        retryPolicy: RetryPolicy(maxAttempts: 3),
        errorLocalizer: AppNetworkErrorLocalizer()
    )
    
    private init() {
        let config = URLSessionConfiguration.default
        // 可在这里配置证书校验、超时等
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        
    }
}
```

`NetworkConfiguration` 是 Client 实例级默认策略；业务 Request 仍可重写 `timeoutInterval`。`RetryPolicy` 默认不重试；只会重试 408、429、5xx 及传输错误。对带副作用的 POST/PUT，请仅在服务端具备幂等键时启用重试。`LoggingInterceptor` 默认不记录 body，并会脱敏 Authorization、Cookie 与 API Key。

### 错误本地化

`NetworkError` 保持为稳定的错误模型，显示文案由 App 注入 `NetworkErrorLocalizing` 决定。以下实现可使用 App 自己的 `Localizable.strings`，并支持按传入的 `Locale` 切换语言：

```swift
struct AppNetworkErrorLocalizer: NetworkErrorLocalizing {
    func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .invalidURL:
            return String(localized: "network.error.invalid_url", bundle: .main, locale: locale)
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
```

在展示错误时使用 Client 的本地化器：

```swift
let message = error.localizedDescription(
    using: AppNetworkClient.shared.configuration.errorLocalizer,
    locale: .current
)
```

### 2. App Request 基类（推荐）

```swift
/// App 层基类：统一注入 client，减少每个业务 Request 的重复代码。
/// T 必须满足 Sendable，才能符合 NativeNetwork 的 Swift 6 并发约束。
class AppRequest<T: Decodable & Sendable>: NetworkRequest, @unchecked Sendable {
    typealias Response = T
    let client: any NetworkClient = AppNetworkClient.shared

    var path: String { "" }
    var method: HTTPMethod { .get }
    var headers: [String: String]? { nil }
}
```

Swift 的 `struct` 不能继承 class；因此采用基类时，业务请求也应使用 `final class`。

### 3. REST 业务请求

```swift
final class GetUserRequest: AppRequest<User>, RestfulRequest, @unchecked Sendable {
    override var path: String { "/users/123" }
    override var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

### 4. GraphQL 业务请求

```swift
final class FetchUserProfileRequest: AppRequest<GraphQLResponse<UserProfile>>, GraphQLRequest, @unchecked Sendable {
    override var path: String { "/graphql" }
    override var method: HTTPMethod { .post }
    var query: String {
        """
        query {
            user {
                id
                name
                email
            }
        }
        """
    }

    // AppRequest 已实现 path/method/headers，因此此处显式覆盖 GraphQL 默认值。
    override var headers: [String: String]? {
        ["Accept": "application/json", "Content-Type": "application/json"]
    }
}
```

### 5. 调用

```swift
// async/await
let user = try await GetUserRequest().execute()
let profile = try await FetchUserProfileRequest().execute()
let userProfile = profile.data
// GraphQL 可以同时返回 data 与 errors；按业务需要处理部分结果。
let graphQLErrors = profile.errors

// Combine
GetUserRequest().executePublisher()
    .sink(receiveCompletion: { _ in }, receiveValue: { user in
        print(user)
    })
    .store(in: &cancellables)
```

## 架构说明

- `NetworkClient`：配置层（baseURL、Session、Interceptor）
- `NetworkRequest`：请求基础协议
- `RestfulRequest` / `GraphQLRequest`：具体协议
- Interceptor：请求/响应拦截

## License

MIT
