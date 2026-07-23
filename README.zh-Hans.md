# NetworkingKit

[English](README.md) · [文档](Docs/README.zh-Hans.md)

NetworkingKit 是面向 iOS、macOS、tvOS 与 watchOS 的原生 Swift 网络库。它无需第三方依赖，提供强类型 REST 和 GraphQL 请求、Swift Concurrency、Combine、HTTP 缓存、认证、重试、可观测性和传输安全能力。

## 核心能力

- 强类型 REST 与 GraphQL 请求，同时支持 `async/await` 和 Combine。
- 按 Client 配置超时、重试、编解码器和多语言错误。
- 使用拦截器统一处理 Header、签名、认证、日志、响应信封和测试行为。
- 支持内存/磁盘 HTTP 缓存、缓存策略、ETag 重新验证、`304`、`Vary` 与离线读取。
- 支持 Token 刷新协调、请求并发限制和按路由熔断。
- 支持 OSLog、OpenTelemetry 桥接、指标、请求 ID 和证书/公钥 pinning。

## 平台要求

- iOS 17+
- macOS 14+
- tvOS 17+
- watchOS 10+
- Swift 6.0+

## 安装

在 Xcode 中选择 **File > Add Package Dependencies**，输入：

```text
https://github.com/relaxfinger/NetworkingKit.git
```

或在 `Package.swift` 中声明：

```swift
dependencies: [
    .package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "2.4.8")
]
```

然后把 `NetworkingKit` 添加到定义请求或调用 API 的 target。

## 快速开始

### 1. 为一个后端创建 Client

一个 Client 统一管理一个后端的基础地址、Session、默认策略和跨请求行为。只有 App 确实要访问不同后端服务时，才需要创建多个 Client。

```swift
import Foundation
import NetworkingKit

final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let configuration = NetworkConfiguration(
        timeoutInterval: 15,
        retryPolicy: RetryPolicy(maxAttempts: 3)
    )

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

### 2. 将 Request 绑定到该 Client

App 级协议让该后端的所有 Request 都使用同一个具体 Client。协议中不放 Header、认证、日志或缓存策略；这些跨请求能力应在 Client 的拦截器与 Transport 中配置。

```swift
protocol AccountRequest: NetworkRequest where Client == AccountAPIClient {}

extension AccountRequest {
    var client: AccountAPIClient { .shared }
}
```

### 3. 定义并调用 REST 请求

```swift
struct User: Decodable, Sendable {
    let id: String
    let name: String
}

struct GetUserRequest: AccountRequest, RestfulRequest {
    typealias Response = User

    var path: String { "/v1/users/123" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

let user = try await GetUserRequest().execute()
```

`GraphQLRequest` 默认提供 `/graphql`、`POST` 和 JSON Header：

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let email: String
}

struct FetchProfileRequest: AccountRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>
    var query: String { "query { user { id email } }" }
}

let response = try await FetchProfileRequest().execute()
let profile = response.data
let errors = response.errors
```

已有 Combine 页面可对同一个 Request 调用 `executePublisher()`。

## 后端 API HTML 文档

NetworkingKit 可以扫描 App 的 Swift 源码，生成可搜索的 HTML 文档：每个后端服务器一个页面，包含配置项和值、按 Feature 分组的端点表、参数、Request 类型和源码文件。

- **`BackendReferenceCommandPlugin`（推荐）：** 在 Xcode 选择 **File → Packages → Generate Backend API Reference**。它会在 App 工程根目录生成可提交、可分享的 `Docs/BackendAPIReference/index.html`。
- **`BackendReferencePlugin`：** 在 App Target 的 **Build Phases → Run Build Tool Plug-ins** 中添加它。它会在每次构建时刷新同一份文档，但 SwiftPM 只能将输出写入 Xcode Derived Data。

需要把 HTML 固定保留在工程中时选择 Command Plugin；只想随构建自动预览时选择 Build Tool Plugin。完整的配置、授权、输出位置、识别规则与排查步骤见[后端 API HTML 文档](Docs/BackendReferencePlugin.zh-Hans.md)。

## 详细文档

README 只保留从安装到首个请求的最短路径。构建生产网络层时，请查阅下列完整双语专题文档：

| 主题 | English | 简体中文 |
| --- | --- | --- |
| 文档索引 | [Docs](Docs/README.md) | [文档索引](Docs/README.zh-Hans.md) |
| Client、Request、REST、GraphQL 与 Combine | [Getting started](Docs/GettingStarted.md) | [快速入门](Docs/GettingStarted.zh-Hans.md) |
| 内存/磁盘缓存、HTTP 语义与离线模式 | [Caching](Docs/Caching.md) | [缓存](Docs/Caching.zh-Hans.md) |
| 统一处理请求与响应 | [Interceptors](Docs/Interceptors.md) | [拦截器](Docs/Interceptors.zh-Hans.md) |
| Bearer Token 与刷新协调 | [Authentication](Docs/Authentication.md) | [认证](Docs/Authentication.zh-Hans.md) |
| 重试、并发限制与熔断 | [Reliability](Docs/Reliability.md) | [稳定性](Docs/Reliability.zh-Hans.md) |
| 日志、追踪与指标 | [Observability](Docs/Observability.md) | [可观测性](Docs/Observability.zh-Hans.md) |
| 稳定错误与本地化 UI 文案 | [Errors](Docs/Errors.md) | [错误与本地化](Docs/Errors.zh-Hans.md) |
| 证书和公钥 pinning | [Security](Docs/Security.md) | [传输安全](Docs/Security.zh-Hans.md) |
| 后端服务器、端点与参数 HTML 文档 | [Backend API reference](Docs/BackendReferencePlugin.md) | [后端 API HTML 文档](Docs/BackendReferencePlugin.zh-Hans.md) |

## Demo

[`Examples/NetworkingKitDemo`](Examples/NetworkingKitDemo) 是 iOS 和 macOS SwiftUI 示例，演示 REST、GraphQL、拦截器、Token 刷新接入、磁盘缓存、按路由熔断、并发限制和本地化错误。

## 开发

运行测试：

```bash
swift test
```

CI 会编译 Public API 兼容性用例，以第三方集成的视角发现源代码兼容性问题。

## 贡献与安全

提交 PR 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全漏洞请按照 [SECURITY.md](SECURITY.md) 中的方式私下报告。

## License

NetworkingKit 使用 [MIT License](LICENSE) 发布。
