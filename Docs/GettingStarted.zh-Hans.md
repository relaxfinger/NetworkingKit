# 快速入门

[English](GettingStarted.md) · [文档索引](README.zh-Hans.md)

本篇建立最小但可持续维护的网络层：一个后端 Client、一个 App 级请求协议、REST 与 GraphQL 请求，以及两种调用方式。

## 1. 按后端边界建模

每个真正不同的后端服务创建一个 `NetworkClient` 类型。账号、内容、支付服务可能有不同 Base URL、凭证、Session 配置或安全策略。生产、预发、测试是同一个后端 Client 的配置，不是不同的 Request 体系。

```swift
import Foundation
import NetworkingKit

enum AccountEnvironment {
    case production
    case staging

    var baseURL: URL {
        switch self {
        case .production: URL(string: "https://api.example.com")!
        case .staging: URL(string: "https://staging-api.example.com")!
        }
    }
}

final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient(environment: .production)

    let baseURL: URL
    let session: URLSession
    let configuration: NetworkConfiguration

    init(environment: AccountEnvironment) {
        baseURL = environment.baseURL
        session = URLSession(configuration: .default)
        configuration = NetworkConfiguration(
            timeoutInterval: 15,
            retryPolicy: RetryPolicy(maxAttempts: 3)
        )
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

通常使用共享实例时采用 `SharedNetworkClient`。如果测试或某个功能需要彼此隔离的实例，Client 也可以只遵循 `NetworkClient`，再注入给具体 Request。

## 2. 用 App 请求协议绑定具体 Client

`NetworkRequest` 有两个关联类型：`Client` 表示后端配置，`Response` 表示解码结果。通过 App 级协议一次绑定 Client；每个业务 Request 只声明自己的响应类型。

```swift
protocol AccountRequest: NetworkRequest where Client == AccountAPIClient {}

extension AccountRequest {
    var client: AccountAPIClient { .shared }
}
```

若有第二个后端，定义第二个 Client 与请求协议。这样可以在编译期避免账号接口误用内容服务的 Client。

## 3. 定义 REST 请求

`RestfulRequest` 提供 `path`、`method`、query、body 和 content type。只把接口自身信息放在这里；公共 Header 和 Token 不应重复写在 Request 中。

```swift
struct User: Codable, Sendable {
    let id: String
    let name: String
}

struct GetUserRequest: AccountRequest, RestfulRequest {
    typealias Response = User

    let id: String
    var path: String { "/v1/users/\(id)" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { [URLQueryItem(name: "include", value: "roles")] }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

struct UpdateUserBody: Codable, Sendable { let name: String }

struct UpdateUserRequest: AccountRequest, RestfulRequest {
    typealias Response = User

    let id: String
    let name: String
    var path: String { "/v1/users/\(id)" }
    var method: HTTPMethod { .put }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { UpdateUserBody(name: name) }
    var contentType: String? { nil } // JSON body 默认使用 application/json。
}
```

成功但无 body 的接口（例如 `204 No Content`）使用 `EmptyResponse` 作为响应类型。

## 4. 定义 GraphQL 请求

`GraphQLRequest` 默认提供 `/graphql`、`POST` 和 JSON 请求 Header。只有服务端不一致时才覆盖这些默认值。

```swift
struct UserProfile: Decodable, Sendable {
    let id: String
    let name: String
    let email: String
}

struct FetchProfileRequest: AccountRequest, GraphQLRequest {
    typealias Response = GraphQLResponse<UserProfile>

    let id: String
    var query: String {
        "query Profile($id: ID!) { user(id: $id) { id name email } }"
    }
    var variables: [String: AnyEncodable]? {
        ["id": AnyEncodable(id)]
    }
    var operationName: String? { "Profile" }
}
```

GraphQL 可能同时返回可用的 `data` 和服务端 `errors`。不要因为 HTTP 请求成功就认为业务操作完全成功，应根据产品规则处理 `errors`。

## 5. 调用请求

新代码使用 Swift Concurrency：

```swift
let user = try await GetUserRequest(id: "42").execute()

let graphQL = try await FetchProfileRequest(id: "42").execute()
let profile = graphQL.data
let serverErrors = graphQL.errors
```

已有 Combine 取消管理的页面可使用 Publisher。订阅时才开始请求，取消订阅会取消底层请求。

```swift
GetUserRequest(id: "42")
    .executePublisher()
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { completion in print(completion) },
        receiveValue: { user in print(user.name) }
    )
    .store(in: &cancellables)
```

## 下一步

- 公共 Header 与响应信封使用[拦截器](Interceptors.zh-Hans.md)。
- Bearer 凭证使用[认证](Authentication.zh-Hans.md)。
- 开始做离线页前先阅读[缓存](Caching.zh-Hans.md)。
- 上线前配置[稳定性](Reliability.zh-Hans.md)与[可观测性](Observability.zh-Hans.md)。
