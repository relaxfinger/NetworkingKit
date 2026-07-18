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
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "2.0.0")
]
```

然后把 `NetworkingKit` 添加到使用它的 target。

## 快速开始

### 1. 实现 App 的 `NetworkClient`

App 通过一个 `NetworkClient` 集中管理基础地址、`URLSession`、传输层、编解码器工厂、拦截器和默认策略。

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

final class AppNetworkClient: NetworkClient, @unchecked Sendable {
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
        session = URLSession(configuration: .default)
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

`NetworkConfiguration` 是不可变的 Client 级默认值；单个 Request 仍可覆盖 `timeoutInterval`。`makeEncoder()` 和 `makeDecoder()` 会为每次操作创建独立的编解码器，避免共享可变配置。通用 Header、认证、请求签名、日志和埋点应统一在 `interceptors` 中配置，不应放在 `AppRequest`。

### 2. 创建 App Request 基类

```swift
class AppRequest<T: Decodable & Sendable>: @unchecked Sendable {
    typealias Response = T
    let client: any NetworkClient = AppNetworkClient.shared
}
```

采用基类时，业务 Request 也必须是 class，因为 Swift 的 `struct` 不能继承 class。基类不应直接遵循 `NetworkRequest`，以便 REST 或 GraphQL 子类获得其各自协议提供的默认值。`AppRequest` 只负责注入 Client 和 Response 类型，不应承载通用 Header、认证或日志；这些跨请求职责属于 `NetworkInterceptor`。

### 3. REST 请求

```swift
struct User: Decodable, Sendable {
    let id: String
    let name: String
}

final class GetUserRequest: AppRequest<User>, RestfulRequest, @unchecked Sendable {
    var path: String { "/users/123" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

需要 JSON body 时，在 `body` 返回任意 `Encodable & Sendable` 值。未指定时库会自动使用 `application/json`。

对于 `204 No Content` 等成功但无 body 的接口，请使用 `EmptyResponse` 作为响应类型：

```swift
final class DeleteUserRequest: AppRequest<EmptyResponse>, RestfulRequest, @unchecked Sendable {
    var path: String { "/users/123" }
    var method: HTTPMethod { .delete }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

### 4. GraphQL 请求

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
}

final class FetchUserProfileRequest: AppRequest<GraphQLResponse<UserProfile>>, GraphQLRequest, @unchecked Sendable {
    var query: String { "query { user { id name } }" }
}
```

GraphQL 的 `GraphQLResponse` 可以同时保留部分 `data` 和服务端 `errors`。`GraphQLRequest` 默认提供 `/graphql`、`POST` 与 JSON `Accept`/`Content-Type` Header；只有服务端端点或请求格式不同才需要显式覆盖。

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

拦截器在请求阶段按数组声明顺序执行：`adapt(_:)` 在配置的 `NetworkTransport` 发送请求之前执行。响应阶段则按反向顺序执行 `transform(response:data:)`，位于 HTTP 状态码校验和解码之前，可用于观察、校验或替换响应数据。任一方法抛错都会转换为 `NetworkError.interceptorFailed`。

### 自定义传输层

默认实现为 `URLSessionTransport`。可覆盖 Client 的 `transport`，以支持确定性测试或自定义网络栈，而无需改动请求定义：

```swift
struct StubTransport: NetworkTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (#"{"id":"42","name":"Ada"}"#.data(using: .utf8)!, response)
    }
}

let transport: any NetworkTransport = StubTransport()
```

### 可观测性与执行控制

添加 `RequestIDInterceptor()` 后，每个请求都会携带 `X-Request-ID`。`NetworkObserving` 会收到每一次传输尝试的开始和结束事件，其中包含状态码、耗时，以及失败时结构化的 `NetworkError`。建议使用 actor 实现该协议，再将数据转发给 OSLog、OpenTelemetry 或自有埋点系统，且不会阻塞请求。

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

将 `RequestConcurrencyLimiter` 配置为 Client 的 `executionController` 可限制同时进行的传输尝试数。重试和一次认证重放均会计入尝试次数，避免故障风暴耗尽设备或服务端资源。

### 内置拦截器

`AuthInterceptor` 会在存在 token 时添加 Bearer Authorization Header：

```swift
AuthInterceptor { TokenStore.shared.accessToken }
```

如果 Bearer Token 会过期，应使用 `RefreshingAuthInterceptor`。必须将**同一个实例**同时注册到 `interceptors` 和 `authentication`：收到 `401` 后，并发请求只会共享一次刷新操作，每个受影响请求至多重放一次。刷新失败会返回 `NetworkError.authenticationRefreshFailed`，不会发生无限重试。

`AccessTokenProviding` 通常应实现为 actor。刷新 Token 时应使用独立的接口或 `URLSession`，避免刷新请求再次进入需要认证的网络链路。

`LoggingInterceptor` 记录请求与响应元数据，默认对 Authorization、Cookie 和 API Key 脱敏，也默认不记录 body。生产环境应谨慎启用 body 日志：

```swift
LoggingInterceptor(
    logBodies: false,
    logger: { message in AppLogger.network.debug("\(message)") }
)
```

### 自定义拦截器

以下示例为每个请求添加 App 通用 Header，应与认证和日志一起在 `AppNetworkClient.interceptors` 中统一注册：

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

仓库 Demo 已实际注册 `DemoCommonHeadersInterceptor`、`AuthInterceptor` 与 `LoggingInterceptor`，通用行为在 Client 统一配置，运行请求时可在 Xcode 控制台看到日志。

## 重试策略

`RetryPolicy` 默认不重试。启用后会对传输错误，以及 HTTP 408、429、5xx 使用带上限的指数退避、jitter 和可选的 `Retry-After` 重试。默认仅重试幂等方法（`GET`、`HEAD`、`PUT`、`DELETE`、`OPTIONS`）。只有服务端支持幂等键时，才应显式将 `POST` 加入可重试方法。

```swift
let policy = RetryPolicy(maxAttempts: 3, initialDelay: 0.25, multiplier: 2)
let idempotentPostPolicy = RetryPolicy(
    maxAttempts: 3,
    retryableMethods: [.get, .head, .put, .delete, .options, .post]
)
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

需要解析业务服务端错误或关联请求追踪时，请使用结构化 HTTP 上下文，不要解析本地化后的错误文案：

```swift
if let networkError = error as? NetworkError,
   let statusCode = networkError.statusCode {
    let requestID = networkError.responseHeaders?["X-Request-ID"]
    let serverBody = networkError.responseBody
    print(statusCode, requestID ?? "", serverBody?.count ?? 0)
}
```

## Demo

打开 `Examples/NetworkingKitDemo/NetworkingKitDemo.xcodeproj`，运行 `NetworkingKitDemo-iOS` 或 `NetworkingKitDemo-macOS`。Demo 覆盖 REST、GraphQL、App 级配置、英语/简体中文错误本地化，以及内置和自定义拦截器。

## License

MIT，详见 [LICENSE](LICENSE)。

## 贡献与安全

开发和 PR 约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全漏洞请按 [SECURITY.md](SECURITY.md) 的方式私下报告。
