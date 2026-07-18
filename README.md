# NativeNetwork

轻量级、纯原生 Swift 网络层，同时支持 **RESTful** 和 **GraphQL**。

- 零第三方依赖（仅使用 Foundation + Combine）
- 支持 `async/await` 和 Combine
- 协议驱动，易于继承和扩展
- 内置 Interceptor 机制（Auth、Logging 等）
- 现代 Swift（Sendable、Actor 友好）

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

### 1. 实现自己的 NetworkClient

```swift
final class AppNetworkClient: NetworkClient {
    static let shared = AppNetworkClient()
    
    let baseURL = URL(string: "https://api.example.com")!
    let session: URLSession
    let interceptors: [any NetworkInterceptor]
    
    private init() {
        let config = URLSessionConfiguration.default
        // 可在这里配置证书校验、超时等
        self.session = URLSession(configuration: config)
        
        self.interceptors = [
            LoggingInterceptor(),
            AuthInterceptor { /* 返回你的 token */ nil }
        ]
    }
}
```

### 2. 创建基类 Request（推荐）

```swift
class AppRequest<T: Decodable>: NetworkRequest {
    typealias Response = T
    let client: NetworkClient = AppNetworkClient.shared
}
```

### 3. 定义业务 Request

#### RESTful 请求

```swift
struct GetUserRequest: AppRequest<User>, RestfulRequest {
    let userId: String
    
    var path: String { "/users/\(userId)" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: Encodable? { nil }
    var contentType: String? { nil }
}
```

#### GraphQL 请求

```swift
struct FetchUserProfileRequest: AppRequest<UserProfile>, GraphQLRequest {
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
let user = try await GetUserRequest(userId: "123").execute()
let profile = try await FetchUserProfileRequest(userId: "123").execute()

// Combine
GetUserRequest(userId: "123").executePublisher()
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
