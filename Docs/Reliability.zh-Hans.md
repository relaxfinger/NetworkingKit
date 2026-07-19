# 稳定性：重试、并发与熔断

[English](Reliability.md) · [文档索引](README.zh-Hans.md)

这些能力解决不同故障问题。重试不能替代修复异常后端，熔断也不应该掩盖产品层错误。

## 重试

`RetryPolicy` 使用带抖动的指数退避。默认策略 `.none` 不重试。启用后，对默认幂等方法 `GET`、`HEAD`、`PUT`、`DELETE`、`OPTIONS` 的临时传输错误与 HTTP `408`、`429`、`5xx` 进行重试，并可遵守数字形式的 `Retry-After` Header。

```swift
let configuration = NetworkConfiguration(
    timeoutInterval: 15,
    retryPolicy: RetryPolicy(
        maxAttempts: 3,
        initialDelay: 0.5,
        multiplier: 2,
        maximumDelay: 5,
        jitterRatio: 0.2,
        respectsRetryAfter: true
    )
)
```

只有后端支持幂等键且 App 会发送该键时，才将 `POST` 加入 `retryableMethods`。否则超时的写操作可能被服务端处理两次。

## 限制并发尝试

`RequestConcurrencyLimiter` 是 actor 实现的 `NetworkExecutionControlling`。它限制同时进行的传输尝试；重试和一次认证重放也算尝试。

```swift
let executionController: (any NetworkExecutionControlling)? =
    RequestConcurrencyLimiter(maximumConcurrentRequests: 6)
```

将控制器配置在 Client 上。并发上限应来自后端和产品的实际测量，而不是随意设一个很大值。页面同时请求多个接口、分页或弱网恢复时尤其有价值。

## 熔断器

熔断器会阻止持续请求异常后端路由。它从 closed 开始，连续失败后变为 open，在 `resetTimeout` 内拒绝请求，之后只允许一个 half-open 探测。探测成功则关闭，失败则重新打开。

多数 App 使用 `RouteCircuitBreakingTransport`。它按 method/host/port/path 为每个路由维护独立熔断器，一个异常接口不会阻断健康路由。

```swift
final class ContentAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = ContentAPIClient()
    let baseURL = URL(string: "https://content.example.com")!
    let session = URLSession(configuration: .default)

    private let circuits = CircuitBreakerRegistry(
        failureThreshold: 5,
        resetTimeout: 30
    )

    var transport: any NetworkTransport {
        RouteCircuitBreakingTransport(
            upstream: URLSessionTransport(session: session),
            registry: circuits
        )
    }
}
```

与缓存一起使用时，将 `CachingTransport` 放到熔断器外层。这样上游路由恢复期间，缓存命中仍可返回。诊断时使用 `await circuits.snapshots()` 查看按路由划分的状态。

## UI 应有的行为

- 只在短小、有边界的策略内后台重试临时错误。
- 重试耗尽后显示正常错误状态。
- 将 `CircuitOpenError` 当作快速的暂时不可用结果，UI 不应立刻再次重试。
- 只有产品允许时才显示缓存内容；需要时明确提示离线或旧数据状态。
