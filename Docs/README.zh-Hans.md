# NetworkingKit 文档

[English](README.md) · [Package README](../README.zh-Hans.md)

这里是生产环境使用的完整参考文档。新 App 可以按下列顺序阅读；已有 App 则按需要进入对应专题。

| 文档 | 适用情况 |
| --- | --- |
| [快速入门](GettingStarted.zh-Hans.md) | 按后端组织 Client、定义强类型 REST/GraphQL 请求，或使用 Combine。 |
| [缓存](Caching.zh-Hans.md) | 优化用户等待、设计离线模式，或与后端约定 HTTP 缓存 Header。 |
| [拦截器](Interceptors.zh-Hans.md) | 一次配置公共 Header、签名、日志、响应信封或测试专用行为。 |
| [认证](Authentication.zh-Hans.md) | 添加 Bearer Token，并在收到 `401` 后安全刷新过期凭证。 |
| [稳定性](Reliability.zh-Hans.md) | 配置重试、限制并发请求或隔离异常后端路由。 |
| [可观测性](Observability.zh-Hans.md) | 添加请求 ID、OSLog、OpenTelemetry 或聚合网络指标。 |
| [错误与本地化](Errors.zh-Hans.md) | 处理稳定错误并显示 App 本地化的用户文案。 |
| [传输安全](Security.zh-Hans.md) | 在有完善证书轮换方案时使用证书或公钥 pinning。 |
| [后端 API HTML 文档](BackendReferencePlugin.zh-Hans.md) | 从 Xcode 工程生成可浏览的后端、端点、参数与配置参考。 |

## 推荐接入顺序

1. 先按[快速入门](GettingStarted.zh-Hans.md)创建一个 Client 和一个 REST 请求。
2. 通过[拦截器](Interceptors.zh-Hans.md)加入公共 Header 与日志。
3. 后端使用 Bearer 凭证时，再加入[认证](Authentication.zh-Hans.md)。
4. 可复用的 `GET` 数据再接入[缓存](Caching.zh-Hans.md)，并与后端约定缓存语义。
5. 业务量和运维要求增长后，加入[稳定性](Reliability.zh-Hans.md)与[可观测性](Observability.zh-Hans.md)。
6. 只有明确需要且具备轮换流程时，才启用[传输安全](Security.zh-Hans.md)中的 pinning。

## 重要边界

- `NetworkClient` 对应一个后端边界，不等于整个 App 只能有一个 Client。
- Request 负责一个接口的 path、method、query、body 与响应类型。
- 拦截器负责共享的请求/响应逻辑，不应在每个 Request 中重复实现。
- Transport 组合缓存、熔断等传输机制。
- App 自己决定哪些数据可以离线保存，以及如何向用户显示错误。

所有文档基于 Swift 6 和包的最低平台版本：iOS 17、macOS 14、tvOS 17、watchOS 10。
