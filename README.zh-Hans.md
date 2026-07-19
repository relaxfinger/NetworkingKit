# NetworkingKit

[English](README.md)

NetworkingKit 是一个面向 iOS、macOS、tvOS 与 watchOS App 的轻量级原生 Swift 网络库，支持 REST、GraphQL、`async/await`、Combine、Swift 6 并发、Client 级配置、错误本地化和拦截器。

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
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "2.3.7")
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

### 2. 创建 App Request 协议

```swift
protocol AppNetworkRequest: NetworkRequest
where Client == AppNetworkClient {}

extension AppNetworkRequest {
    var client: AppNetworkClient {
        .shared
    }
}
```

使用 App 级协议可以避免在每个 Request 中重复提供 Client。`NetworkRequest` 同时绑定具体的 `Client` 类型与 `Response` 类型；`AppNetworkRequest` 通过 `Client == AppNetworkClient` 直接约束 Client，但不使用 `any NetworkClient` 抹除它，具体 REST 或 GraphQL 请求只声明自身的 `Response`。这样能在编译期避免某个后端的 Request 被错误地绑定到另一个后端的 Client。有多个后端 Client 时，为每个 Client 定义一个等价的请求协议。这种写法同时支持 `struct` 与 class。`AppNetworkRequest` 不应承载通用 Header、认证或日志；这些跨请求职责属于 `NetworkInterceptor`。

### 3. REST 请求

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

需要 JSON body 时，在 `body` 返回任意 `Encodable & Sendable` 值。未指定时库会自动使用 `application/json`。

对于 `204 No Content` 等成功但无 body 的接口，请使用 `EmptyResponse` 作为响应类型：

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

### 4. GraphQL 请求

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
}

struct FetchUserProfileRequest: AppNetworkRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>
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

使用 `OSLogNetworkObserver(subsystem: "com.example.app")` 可零依赖接入统一日志。若使用 OpenTelemetry，请以具体 SDK 实现 `OpenTelemetryExporting`，再注册 `OpenTelemetryNetworkObserver(exporter:)`；NetworkingKit 本身不强依赖任何 SDK。

添加 `RequestIDInterceptor()` 后，每个请求都会携带 `X-Request-ID`。`NetworkObserving` 会收到每一次传输尝试的开始和结束事件，其中包含状态码、耗时，以及失败时结构化的 `NetworkError`。建议使用 actor 实现该协议，再将数据转发给 OSLog、OpenTelemetry 或自有埋点系统，且不会阻塞请求。

需要与厂商无关的聚合健康指标时，可添加 `NetworkMetricsObserver`。其 actor 收集器提供请求总量、传输失败数、HTTP 状态码分布和平均尝试耗时；定时读取快照后可用任意指标 SDK 导出。

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

将 `RequestConcurrencyLimiter` 配置为 Client 的 `executionController` 可限制同时进行的传输尝试数。重试和一次认证重放均会计入尝试次数，避免故障风暴耗尽设备或服务端资源。

### HTTP 缓存、离线模式与传输安全

缓存不只是性能优化，更直接影响用户体验：商品列表或个人资料可以更快显示，网络和服务端压力更小，已经看过的内容在无网时仍有机会可用。`CachingTransport` 只缓存成功的 `GET` 响应；`POST`、`PUT`、`PATCH` 和 `DELETE` 等写操作始终走网络，避免 App 把旧的写入结果误当成一次已经完成的业务操作。

#### 选择缓存实现

| 实现 | 存活时间 | 适合场景 | 容量行为 |
| --- | --- | --- | --- |
| `InMemoryResponseCache` | 仅当前进程 | 可接受冷启动的少量、非敏感页面数据 | 以请求 key 数量为上限，按最近最少使用顺序淘汰 |
| `DiskResponseCache` | 跨 App 启动保留 | 商品目录、文章、基础资料和支持离线的读取接口 | 保存在 App 私有目录的 JSON 文件；超过 `maximumSize` 后按最近最少访问顺序清理 |
| `NetworkResponseCaching` | 由 App 自行实现 | 加密存储、数据库或特定淘汰规则 | 由实现决定 |

生产环境中如果希望跨启动保留缓存，应由 Client 持有一个缓存实例。不要在 `transport` 属性里每次临时创建缓存，否则属性每次计算都会丢失已有内容。

```swift
final class CatalogAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = CatalogAPIClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession

    private let responseCache = DiskResponseCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CatalogHTTPResponses", isDirectory: true),
        maximumSize: 50 * 1_024 * 1_024
    )

    var transport: any NetworkTransport {
        CachingTransport(
            upstream: URLSessionTransport(session: session),
            cache: responseCache,
            policy: .returnCacheElseLoad,
            defaultTTL: 5 * 60
        )
    }

    private init() {
        session = URLSession(configuration: .default)
    }
}
```

#### 选择读取策略

`NetworkCachePolicy` 决定已有缓存能否满足一次 `GET` 请求。对于 `.networkOnly` 和 `.returnCacheElseLoad`，后续成功的网络响应仍可能更新缓存。

| 策略 | 行为 | 常见场景 |
| --- | --- | --- |
| `.networkOnly` | 始终请求上游；跳过缓存读取，但会保存符合条件的成功响应 | 下拉刷新、必须展示服务器最新状态的页面、排查问题 |
| `.returnCacheElseLoad` | 立即返回仍新鲜的缓存；缓存缺失、已过期或带有 `no-cache` 时请求网络，并在可能时重新验证 | 商品目录、只读资料、配置、文章详情等默认选择 |
| `.returnCacheDontLoad` | 完全不访问网络；即使缓存已过期也返回匹配内容，没有条目则抛出 `CacheMissError` | 明确的离线模式或仅离线可用的页面 |

例如，离线下载页可通过同一个 `DiskResponseCache` 组合出 `.returnCacheDontLoad` 的 Transport。捕获 `CacheMissError` 后提示用户该内容尚未下载。

```swift
let offlineTransport = CachingTransport(
    upstream: URLSessionTransport(session: session),
    cache: responseCache,
    policy: .returnCacheDontLoad
)
```

#### 与后端的 HTTP 缓存规则协作

App 决定“缓存保存在哪里”和“采用何种读取策略”；后端应决定“一份数据在多长时间内有效”。NetworkingKit 会处理以下标准响应 Header：

| 服务端 Header | NetworkingKit 的行为 | 推荐的后端用法 |
| --- | --- | --- |
| `Cache-Control: max-age=300` | 将响应视为 300 秒内新鲜 | 可以短时间安全复用的公开数据或当前用户可见的读取数据 |
| `Cache-Control: no-cache` | 保存响应，但每次复用前都要求走网络重新验证 | 可以本地保存，但每次展示前都必须确认是否变化的数据 |
| `Cache-Control: no-store` | 不保存响应 | Token、一次性密钥、高敏感账户或支付数据 |
| `Expires` | 在没有 `max-age` 时使用 | 兼容旧后端；新接口优先使用 `Cache-Control: max-age` |
| `ETag: "version"` | 匹配的缓存过期后添加 `If-None-Match`；收到 `304 Not Modified` 时复用本地 body，并刷新元数据和 TTL | 后端能够低成本判断资源是否变化的读取接口 |
| `Vary: Accept-Language` | 针对相关请求 Header 的不同值保存独立变体 | 多语言内容、内容协商或其他依赖 Header 的响应 |

当响应既没有 `Cache-Control` 也没有 `Expires` 时，会使用 `defaultTTL`（默认五分钟）。如果请求本身带有 `Cache-Control: no-store`，NetworkingKit 不会读取或写入对应缓存。带有 `Vary: *` 的响应无法安全匹配，因此永远不会被保存。

典型的前后端协作流程如下：

```text
1. GET /articles/42 → 200
   Cache-Control: max-age=300
   ETag: "article-42-v7"

2. 五分钟后，App 发送：
   GET /articles/42
   If-None-Match: "article-42-v7"

3. 若内容未变，后端返回 304 Not Modified。
   NetworkingKit 保留本地响应 body，合并服务端返回的 Header，并刷新过期时间。
```

这样无需重复下载同一份 JSON body，同时仍由后端控制新鲜度。如果缓存过期后网络重新验证失败，`.returnCacheElseLoad` 会把错误交给 App，而不会悄悄展示旧数据；只有产品明确支持离线旧数据时才应使用 `.returnCacheDontLoad`。

#### 缓存的运维与失效

可读取磁盘缓存统计信息用于诊断或存储展示；用户退出登录、切换账号时，应清理与用户相关的缓存。缓存目录必须是 App 私有目录，认证后的响应不要放在共享位置。

```swift
let statistics = await responseCache.statistics()
print("Cache files: \(statistics.entryCount), bytes: \(statistics.totalSize)")

func signOut() async {
    await responseCache.removeAll()
    // Clear credentials and App state after the cache is removed.
}
```

对于写操作改变的数据，优先使用后端的版本控制或 ETag 规则；如需按 URL 等精确清理，可实现自定义 `NetworkResponseCaching`。内置缓存只提供 `removeAll()`，以保持默认行为简单、安全。

使用 `CertificatePinningEvaluator` 和 `ServerTrustSessionDelegate` 可按 Host 固定叶子证书的 DER 数据。证书轮换期间至少保留两个 pin，并在接受 pin 前继续使用系统信任校验。

```swift
let evaluator = CertificatePinningEvaluator(pinnedCertificates: [
    "api.example.com": [currentCertificateDER, nextCertificateDER]
])
let delegate = ServerTrustSessionDelegate(evaluator: evaluator)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

证书轮换时可使用 `PublicKeyHashPinningEvaluator`，它接受叶子证书公钥 bytes 的 SHA-256 哈希。在切换证书前，请同时在 `pinnedHashes` 中保留当前和备份哈希。

### 断路器

使用 `CircuitBreakingTransport` 包装 Transport，可在上游连续失败时快速拒绝请求，避免持续冲击异常服务。它通过 `CircuitBreakerSnapshot` 提供轻量健康指标，并在 `resetTimeout` 到期后只允许一个半开恢复探测请求。

```swift
let transport = CircuitBreakingTransport(
    upstream: URLSessionTransport(session: session),
    circuitBreaker: CircuitBreaker(failureThreshold: 5, resetTimeout: 30)
)
```

多数 App 应使用 `RouteCircuitBreakingTransport`。它会为每个 method/host/port/path 组合建立独立断路器，因此一个异常接口不会阻断其他健康 API。将缓存放在它的外层，可以让上游恢复期间的缓存命中继续可用；`CircuitBreakerRegistry.snapshots()` 则可返回按路由 key 划分的状态，供诊断和遥测使用。

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

## 开发

### Public API 兼容性

每个 PR 都会编译 `NetworkingKitAPICompatibilityTests`。它模拟第三方 App，并且只导入公开模块 API，覆盖 Client 配置、REST、GraphQL、缓存、路由级断路器、观测、重试配置与 pinning。任何使该样例无法编译的改动，都应视为源码兼容性破坏，并在大版本迁移说明中明确记录。

`PerformanceTests` 还会测量 JSON 解码和 URLRequest 构建。它们用于捕获回归，而不是作为不同设备之间的绝对性能指标；如果热点路径的执行时间或分配明显变化，应进一步分析。

## License

MIT，详见 [LICENSE](LICENSE)。

## 贡献与安全

开发和 PR 约定见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全漏洞请按 [SECURITY.md](SECURITY.md) 的方式私下报告。

CI 会运行 Debug 测试、Release 构建和两个 Demo target。匹配 `v*` 的 tag 会运行相同验证；若 GitHub Release 尚不存在，则自动创建。
