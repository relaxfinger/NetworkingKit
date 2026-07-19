# Observability: request IDs, logs, traces, and metrics

[简体中文](Observability.zh-Hans.md) · [Documentation index](README.md)

Network observability should answer: which request failed, for which route, how often, and how long did attempts take? NetworkingKit keeps this vendor-neutral through `NetworkObserving`.

## Request IDs and lifecycle events

Add `RequestIDInterceptor()` to send an `X-Request-ID` when the request does not already have one. Every transport attempt emits `.started` and `.finished` events. A finished event includes status code when available, duration, and structured `NetworkError`.

```swift
let metrics = NetworkMetrics()

let observers: [any NetworkObserving] = [
    OSLogNetworkObserver(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app"),
    NetworkMetricsObserver(metrics: metrics)
]
```

Register `RequestIDInterceptor()` in `interceptors` and this array in the client's `observers` property. Observers are asynchronous, so they should forward data without blocking request completion.

## Aggregate metrics

`NetworkMetrics` is an actor that tracks completed attempts, successes, failures, transport failures, HTTP status-code counts, and average duration.

```swift
let snapshot = await metrics.snapshot()
print(snapshot.totalCount)
print(snapshot.failureCount)
print(snapshot.statusCodeCounts)
print(snapshot.averageDuration)
```

Snapshot periodically on an App-defined schedule and export the data through your metrics SDK. Call `await metrics.reset()` only after you have exported a period and genuinely want interval rather than lifetime values.

## OpenTelemetry bridge

NetworkingKit has no OpenTelemetry dependency. Adapt your SDK behind `OpenTelemetryExporting`, then register `OpenTelemetryNetworkObserver(exporter:)`.

```swift
actor TelemetryExporter: OpenTelemetryExporting {
    func export(name: String, attributes: [String: String]) async {
        // Convert attributes into your OpenTelemetry SDK's event/span API.
    }
}

let observer = OpenTelemetryNetworkObserver(exporter: TelemetryExporter())
```

Avoid exporting tokens, cookies, request bodies, or user identifiers without an explicit privacy review. Prefer request ID, method, route-level URL information, status, duration, and classified error type.

## Custom observer

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

Use observers for telemetry, not business control flow. A screen should still derive its state from the request result or `NetworkError`.
