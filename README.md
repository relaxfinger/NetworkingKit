# NativeNetwork

轻量级、纯原生 Swift 网络层，同时支持 **RESTful** 和 **GraphQL**。

- 零第三方依赖（仅使用 Foundation + Combine）
- 支持 `async/await` 和 Combine
- 协议驱动，易于继承和扩展
- 内置 Interceptor 机制（Auth、Logging 等）
- Swift 6 strict concurrency（Sendable、Actor 友好）
- 可配置 JSON 编解码、退避重试与默认脱敏日志

## 安装

### Swift Package Manager

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/NativeNetwork.git", from: "1.0.0")
]
```

或在 Xcode 中：`File` → `Add Package Dependencies...`

## 快速开始

## iOS 与 macOS Demo

仓库的 `Examples/NativeNetworkDemoApp/NativeNetworkDemo.xcodeproj` 含两个原生 SwiftUI App scheme：`NativeNetworkDemo-iOS` 与 `NativeNetworkDemo-macOS`。选择对应 scheme 并在 Xcode 中运行，即可查看 REST 与 GraphQL 调用。

示例使用 JSONPlaceholder 与 Rick and Morty GraphQL API，仅用于学习和本地验证；生产应用应使用自己的后端地址、认证与日志策略。

### 1. 实现自己的 NetworkClient

```swift
final class AppNetworkClient: NetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()
    
    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let interceptors: [any NetworkInterceptor]
    let decoder: JSONDecoder
    let retryPolicy = RetryPolicy(maxAttempts: 3)
    
    private init() {
        let config = URLSessionConfiguration.default
        // 可在这里配置证书校验、超时等
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        self.interceptors = [
            LoggingInterceptor(),
            AuthInterceptor { /* 返回你的 token */ nil }
        ]
    }
}
```

`RetryPolicy` 默认不重试；只会重试 408、429、5xx 及传输错误。对带副作用的 POST/PUT，请仅在服务端具备幂等键时启用重试。`LoggingInterceptor` 默认不记录 body，并会脱敏 Authorization、Cookie 与 API Key。

### 2. 定义业务 Request

```swift
struct GetUserRequest: RestfulRequest {
    typealias Response = User
    let client: any NetworkClient
    let userId: String
    
    var path: String { "/users/\(userId)" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}
```

### 3. GraphQL 请求

```swift
struct FetchUserProfileRequest: GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>
    let client: any NetworkClient
    let userId: String
    
    var query: String {
        """
        query GetUser($id: ID!) {
            user(id: $id) {
                id
                name
                email
            }
        }
        """
    }
    
    var variables: [String: AnyEncodable]? {
        ["id": AnyEncodable(userId)]
    }
}
```

### 4. 调用

```swift
// async/await
let user = try await GetUserRequest(client: AppNetworkClient.shared, userId: "123").execute()
let profile = try await FetchUserProfileRequest(client: AppNetworkClient.shared, userId: "123").execute()
let userProfile = profile.data
// GraphQL 可以同时返回 data 与 errors；按业务需要处理部分结果。
let graphQLErrors = profile.errors

// Combine
GetUserRequest(client: AppNetworkClient.shared, userId: "123").executePublisher()
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
