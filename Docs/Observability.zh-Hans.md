# 可观测性：请求 ID、日志、追踪与指标

[English](Observability.md) · [文档索引](README.zh-Hans.md)

网络可观测性应回答：哪个请求失败、哪个路由、发生频率如何、每次尝试耗时多久？NetworkingKit 通过 `NetworkObserving` 保持与厂商无关。

## 请求 ID 与生命周期事件

加入 `RequestIDInterceptor()` 后，请求在没有现有 ID 时会携带 `X-Request-ID`。每一次传输尝试都会产生 `.started` 和 `.finished` 事件；结束事件包含可用时的状态码、耗时和结构化 `NetworkError`。

```swift
let metrics = NetworkMetrics()

let observers: [any NetworkObserving] = [
    OSLogNetworkObserver(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app"),
    NetworkMetricsObserver(metrics: metrics)
]
```

将 `RequestIDInterceptor()` 注册到 `interceptors`，将上面的数组赋给 Client 的 `observers`。Observer 是异步的，应转发数据而不阻塞请求完成。

## 聚合指标

`NetworkMetrics` 是 actor，记录已完成尝试数、成功数、失败数、传输失败数、HTTP 状态码分布和平均耗时。

```swift
let snapshot = await metrics.snapshot()
print(snapshot.totalCount)
print(snapshot.failureCount)
print(snapshot.statusCodeCounts)
print(snapshot.averageDuration)
```

按 App 自己的周期读取快照，再用指标 SDK 导出。只有在已导出一个周期、且确实想要区间值而不是累计值时，才调用 `await metrics.reset()`。

## OpenTelemetry 桥接

NetworkingKit 不依赖 OpenTelemetry。将实际 SDK 封装到 `OpenTelemetryExporting`，再注册 `OpenTelemetryNetworkObserver(exporter:)`。

```swift
actor TelemetryExporter: OpenTelemetryExporting {
    func export(name: String, attributes: [String: String]) async {
        // Convert attributes into your OpenTelemetry SDK's event/span API.
    }
}

let observer = OpenTelemetryNetworkObserver(exporter: TelemetryExporter())
```

没有明确隐私审查时，不要导出 Token、Cookie、请求 body 或用户标识。优先使用请求 ID、method、路由级 URL 信息、状态码、耗时与分类错误类型。

## 自定义 Observer

```swift
actor AppNetworkObserver: NetworkObserving {
    func record(_ event: NetworkEvent) async {
        switch event {
        case let .started(context):
            print("Started \(context.id) \(context.method.rawValue)")
        case let .finished(context, outcome):
            print("Finished \(context.id), status: \(outcome.statusCode ?? 0), duration: \(outcome.duration)")
        }
    }
}
```

Observer 用于遥测，而不是业务控制流。页面状态仍应由请求结果或 `NetworkError` 决定。
