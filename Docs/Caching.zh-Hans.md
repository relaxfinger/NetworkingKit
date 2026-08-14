# HTTP 缓存与离线读取

[English](Caching.md) · [文档索引](README.zh-Hans.md)

缓存是用户体验决策。它可以让已经看过的内容更快出现、降低网络和服务端压力，并提供明确设计过的离线模式；但它不能代替“哪些数据可以安全保存”的产品判断。

`CachingTransport` 只保存成功的 `GET` 响应。写操作始终使用上游 Transport，避免旧写入结果被误判成已完成的业务操作。

## 选择存储方式

| 类型 | 存活时间 | 适用数据 | 淘汰方式 |
| --- | --- | --- | --- |
| `InMemoryResponseCache` | 当前进程 | 少量、非敏感页面数据 | 超过 `capacity` 后按最近最少使用的请求 key 淘汰 |
| `DiskResponseCache` | 跨 App 启动 | 商品目录、文章、基础资料和支持离线的读取 | 超过 `maximumSize` 字节后按最近最少访问的文件淘汰 |
| `NetworkResponseCaching` | App 自定义 | 加密存储、数据库或自定义失效模型 | App 自定义 |

缓存只能创建一次并由 Client 持有。在 `transport` getter 中临时创建缓存，每次访问都会得到新实例，无法保留内容。

```swift
final class CatalogAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = CatalogAPIClient()

    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .default)
    let defaultProfile = NetworkClientProfile()

    private let cache = DiskResponseCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CatalogHTTPResponses", isDirectory: true),
        maximumSize: 50 * 1_024 * 1_024
    )

    var transport: any NetworkTransport {
        CachingTransport(
            upstream: RequestCoalescingTransport(
                upstream: URLSessionTransport(session: session)
            ),
            cache: cache,
            policy: .returnCacheElseLoad,
            defaultTTL: 5 * 60
        )
    }
}
```

## 选择读取行为

| `NetworkCachePolicy` | 行为 | 适用场景 |
| --- | --- | --- |
| `.networkOnly` | 跳过缓存读取并始终访问上游；符合条件的成功响应仍可更新缓存 | 下拉刷新、必须显示最新状态的页面、排查问题 |
| `.returnCacheElseLoad` | 立即返回新鲜缓存；缺失、过期或 `no-cache` 时访问上游 | 商品目录、文章、只读资料和配置的默认选择 |
| `.returnCacheDontLoad` | 完全不访问网络；即使缓存过期也返回匹配条目，无条目时抛出 `CacheMissError` | 明确的离线模式 |
| `.staleWhileRevalidate(maxStale:)` | 正常返回新鲜缓存；符合时限的旧缓存立即返回，并在后台刷新 | 可接受短暂旧数据的快速重复加载 |

`returnCacheElseLoad` 不会在重新验证失败后悄悄使用过期数据。产品明确要提供离线数据时，使用同一个缓存组合出 `.returnCacheDontLoad` 的离线 Client/Transport，并针对 `CacheMissError` 显示清晰的空状态。

## 覆盖单个请求的策略

`NetworkRequest.cachePolicy` 默认为 `nil`，即沿用 `CachingTransport` 的默认策略。单个接口需要不同读取行为时，可以直接覆盖，无需创建另一个 Client。

```swift
struct RefreshCatalogRequest: RestfulRequest {
    typealias Response = Catalog
    let client = CatalogAPIClient.shared
    let path = "/catalog"
    let method = HTTPMethod.get
    let queryItems: [URLQueryItem]? = nil
    let body: (any Encodable & Sendable)? = nil
    let contentType: String? = nil

    let cachePolicy: NetworkCachePolicy? = .networkOnly
}
```

当 Client 的 Transport 遵循 `RequestCachePolicyTransport` 时，请求级策略会生效。`CachingTransport` 与 `RequestCoalescingTransport` 均已遵循；请求合并包装层会把策略继续传递给支持缓存的上游 Transport。

## 合并并发读取

`RequestCoalescingTransport` 会让等价的并发 `GET` 与 `HEAD` 请求共享一次上游访问。默认 key 会对 Method、绝对 URL 和请求 Header 做哈希，同时排除 Request ID 与分布式追踪 Header。因此不同认证或语言变体不会错误共享。

```swift
let upstream = RequestCoalescingTransport(
    upstream: URLSessionTransport(session: session)
)
let transport = CachingTransport(upstream: upstream, cache: cache)
```

它只合并正在执行的请求，不保存已完成响应；如需后续复用，应与 `CachingTransport` 组合。只有 App 已明确响应变体规则时，才应提供自定义 `keyProvider`。

## 使用 stale-while-revalidate

`.staleWhileRevalidate(maxStale:)` 会在匹配缓存的过期时间不超过允许窗口时立即返回旧值，并使用非结构化后台任务重新验证。存在 ETag 时会发送 `If-None-Match`；`304` 或新的成功响应都会更新缓存，供下次读取。没有缓存或缓存过旧时，调用方仍会等待上游响应。

应把 `RequestCoalescingTransport` 放在缓存的直接上游，防止多个旧缓存读取触发重复重新验证。后台刷新是尽力而为；如果当前交互必须拿到最新模型，仍应显式使用 `.networkOnly`。

## 与后端约定 HTTP 语义

App 决定缓存位置与读取策略，后端控制新鲜度。NetworkingKit 支持：

| Header | 行为 |
| --- | --- |
| `Cache-Control: max-age=300` | 将响应视为 300 秒内新鲜。 |
| `Cache-Control: no-cache` | 可保存，但每次复用前必须重新验证。 |
| `Cache-Control: no-store` | 不保存响应；请求带有此指令时也跳过缓存读取。 |
| `Expires` | 没有 `max-age` 时使用。 |
| `ETag` | 匹配缓存过期后添加 `If-None-Match`；`304 Not Modified` 复用本地 body 并刷新 Header/过期时间。 |
| `Vary` | 按相关请求 Header 保存独立变体，例如 `Accept-Language`；`Vary: *` 永不保存。 |

响应没有 `Cache-Control` 和 `Expires` 时才使用 `defaultTTL`。新后端的可复用读取接口建议返回 `Cache-Control: max-age` 和 `ETag`。

```text
GET /articles/42 → 200
Cache-Control: max-age=300
ETag: "article-42-v7"

五分钟后：
GET /articles/42
If-None-Match: "article-42-v7"

内容未变 → 304 Not Modified
```

`304` 避免重复下载原始 JSON，同时仍由后端决定数据是否变化。

## 生命周期、隐私与失效

认证后的响应必须保存在 App 私有目录。用户退出登录或切换账号时，清理用户相关内容。

```swift
let statistics = await cache.statistics()
print("Cache files: \(statistics.entryCount), bytes: \(statistics.totalSize)")

func signOut() async {
    await cache.removeAll()
    // Then clear credentials and user-specific App state.
}
```

内置缓存有意只提供 `removeAll()`。写操作后若产品需要按 URL 或实体精确失效，请实现带索引和失效规则的 `NetworkResponseCaching`。不要缓存 Token、一次性密钥、支付数据或登出后无法安全删除的数据。

## 应覆盖的测试

- 第一次 `GET` 保存符合条件的成功响应。
- `.returnCacheElseLoad` 下新鲜缓存不会访问上游。
- 过期 ETag 缓存发送 `If-None-Match` 并处理 `304`。
- 不同 `Vary: Accept-Language` 不会共享响应。
- 离线模式命中返回缓存，未命中报告 `CacheMissError`。
- 请求级 `.networkOnly` 会绕过新鲜缓存并更新缓存内容。
- stale-while-revalidate 会立即返回旧缓存并刷新存储结果。
- 等价并发读取只访问一次上游，认证/Header 变体仍保持隔离。
- 登出会移除持久化的用户缓存。
