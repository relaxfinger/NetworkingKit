# 拦截器

[English](Interceptors.md) · [文档索引](README.zh-Hans.md)

拦截器是 Client 请求链路上的可复用处理点。它适合多个接口共享的行为：公共 Header、请求 ID、签名、认证、日志、响应信封转换，以及测试用的请求/响应行为。业务接口的 path、query、body 不应放入拦截器，仍属于 `RestfulRequest` 或 `GraphQLRequest`。

## 执行顺序

当 `interceptors: [A, B, C]` 时：

1. 请求阶段的 `adapt(_:)` 按 `A → B → C` 执行，再交给 Transport。
2. 响应阶段的 `transform(response:data:)` 按 `C → B → A` 执行，随后才进行 HTTP 状态码校验和解码。

响应阶段反向执行，使外层拦截器可以看到内层处理后的结果。任一方法抛错都会转换为 `NetworkError.interceptorFailed`。

## 在 Client 中一次注册

```swift
final class APIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = APIClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .default)

    var interceptors: [any NetworkInterceptor] {
        [
            RequestIDInterceptor(),
            CommonHeadersInterceptor(),
            LoggingInterceptor(logBodies: false) { print($0) }
        ]
    }
}
```

`LoggingInterceptor` 默认脱敏 body。生产环境除非接口数据明确允许记录，否则保持 `logBodies: false`。

## 示例：公共 Header

```swift
struct CommonHeadersInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue("1.0.0", forHTTPHeaderField: "X-App-Version")
        return request
    }
}
```

这样 App 级 Header 始终一致。确实需要不同 Header 的单个接口，仍可通过 `NetworkRequest.headers` 返回。

## 示例：拆开统一响应信封

当一个后端的所有接口都有相同 JSON 外层信封时，可用响应转换。转换逻辑必须校验自己的假设，并只返回 Request 的 `Response` 应解码的 bytes。

```swift
struct EnvelopeInterceptor: NetworkInterceptor {
    func transform(response: URLResponse, data: Data) async throws -> Data {
        // 实际 App 中应解码与后端契约一致的具体信封模型，
        // 再只编码 payload，供 Request 的 Response 解码。
        data
    }
}
```

异构信封应优先使用具体响应模型或自定义 `NetworkTransport`，不要引入不安全的 `Any` 解码。转换钩子适合契约稳定、可测试的统一信封。

## 测试建议

每个拦截器单独使用 `URLRequest` 和确定响应数据测试。完整 Client 至少测一次执行顺序：Header 与认证应在 Transport 前执行，信封转换应在解码前执行。需要完全可控响应的接口测试，通常直接使用小型 `NetworkTransport` stub 更简单。
