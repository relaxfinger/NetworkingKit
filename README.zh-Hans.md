# NetworkingKit

[English](README.md)

NetworkingKit 是一个面向 iOS 与 macOS App 的轻量级原生 Swift 网络库，支持 REST、GraphQL、`async/await`、Combine、Swift 6 并发、Client 级配置、错误本地化和拦截器。

## 特性

- 无第三方依赖，仅使用 Foundation 与 Combine。
- 使用简洁的协议式 API 支持 REST 与 GraphQL。
- 同时提供 `async/await` 和 Combine。
- 对外 API 遵循 Swift 6 `Sendable` 并发约束。
- 可按 `NetworkClient` 配置超时、重试和错误文案。
- 内置 `AuthInterceptor` 与默认脱敏的 `LoggingInterceptor`。
- 支持自定义请求/响应拦截器。

## 平台要求

- iOS 17+
- macOS 14+
- tvOS 17+
- watchOS 10+
- Swift 6.0+

## 安装

通过 Xcode 的 **File > Add Package Dependencies** 添加，或在 `Package.swift` 中声明：

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "1.0.0")
]
```

然后把 `NetworkingKit` 添加到使用它的 target。

## 快速开始

### 1. 实现 App 的 `NetworkClient`

App 通过一个 `NetworkClient` 集中管理基础地址、`URLSession`、解码器、拦截器和默认策略。

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
        session = URLSession(configuration: .default)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
}
```

`NetworkConfiguration` 是不可变的 Client 级默认值；单个 Request 仍可覆盖 `timeoutInterval`。

### 2. 创建 App Request 基类

```swift
class AppRequest<T: Decodable & Sendable>: NetworkRequest, @unchecked Sendable {
    typealias Response = T
    let client: any NetworkClient = AppNetworkClient.shared

    var path: String { "" }
    var method: HTTPMethod { .get }
    var headers: [String: String]? { nil }
}
```

采用基类时，业务 Request 也必须是 class，因为 Swift 的 `struct` 不能继承 class。

### 3. REST 请求

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

需要 JSON body 时，在 `body` 返回任意 `Encodable & Sendable` 值。未指定时库会自动使用 `application/json`。

### 4. GraphQL 请求

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
}

final class FetchUserProfileRequest: AppRequest<GraphQLResponse<UserProfile>>, GraphQLRequest, @unchecked Sendable {
    override var path: String { "/graphql" }
    override var method: HTTPMethod { .post }
    override var headers: [String: String]? {
        ["Accept": "application/json", "Content-Type": "application/json"]
    }
    var query: String { "query { user { id name } }" }
}
```

GraphQL 的 `GraphQLResponse` 可以同时保留部分 `data` 和服务端 `errors`。

### 5. 发起调用

```swift
let user = try await GetUserRequest().execute()

let response = try await FetchUserProfileRequest().execute()
let profile = response.data
let graphQLErrors = response.errors
```

Combine 会在订阅时才发起请求，取消订阅会取消底层任务：

```swift
GetUserRequest()
    .executePublisher()
    .sink(receiveCompletion: { print($0) }, receiveValue: { print($0.name) })
    .store(in: &cancellables)
```

## NetworkInterceptor

`NetworkInterceptor` 用于处理跨请求的逻辑，例如认证、公共 Header、签名、日志、埋点、响应观察和测试 mock。

拦截器按数组声明顺序执行：`adapt(_:)` 在 `URLSession` 发送请求之前执行，`intercept(response:data:)` 在接收响应之后、HTTP 状态码校验和解码之前执行。任一方法抛错都会转换为 `NetworkError.interceptorFailed`。

### 内置拦截器

`AuthInterceptor` 会在存在 token 时添加 Bearer Authorization Header：

```swift
AuthInterceptor { TokenStore.shared.accessToken }
```

`LoggingInterceptor` 记录请求与响应元数据，默认对 Authorization、Cookie 和 API Key 脱敏，也默认不记录 body。生产环境应谨慎启用 body 日志：

```swift
LoggingInterceptor(
    logBodies: false,
    logger: { message in AppLogger.network.debug("\(message)") }
)
```

### 自定义拦截器

以下示例为每个请求添加业务 Header：

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

仓库 Demo 已实际注册 `DemoRequestHeaderInterceptor` 与 `LoggingInterceptor`，运行请求时可在 Xcode 控制台看到日志。

## 重试策略

`RetryPolicy` 默认不重试。启用后会对传输错误，以及 HTTP 408、429、5xx 使用指数退避重试。POST、PUT 等有副作用的请求，只有服务端支持幂等键时才建议重试。

```swift
let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, multiplier: 2)
```

## 错误本地化

`NetworkError` 只表达稳定的错误语义；App 可通过 `NetworkErrorLocalizing` 决定多语言显示文案：

```swift
struct AppNetworkErrorLocalizer: NetworkErrorLocalizing {
    func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .unauthorized:
            return String(localized: "network.error.unauthorized", bundle: .main, locale: locale)
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

打开 `Examples/NetworkingKitDemo/NetworkingKitDemo.xcodeproj`，运行 `NetworkingKitDemo-iOS` 或 `NetworkingKitDemo-macOS`。Demo 覆盖 REST、GraphQL、App 级配置、英语/简体中文错误本地化，以及内置和自定义拦截器。

## License

MIT，详见 [LICENSE](LICENSE)。
