# Reliability: retry, concurrency, and circuit breakers

[简体中文](Reliability.zh-Hans.md) · [Documentation index](README.md)

These mechanisms address different failure modes. Do not use retries as a substitute for an unavailable backend, and do not use a circuit breaker to hide a product error.

## Retries

`RetryPolicy` uses exponential backoff with jitter. The default policy is `.none`. When enabled, it retries transient transport failures and HTTP `408`, `429`, and `5xx` only for idempotent methods by default: `GET`, `HEAD`, `PUT`, `DELETE`, and `OPTIONS`. It can respect a numeric `Retry-After` header.

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

Only add `POST` to `retryableMethods` when the backend supports an idempotency key and the App sends one. Otherwise a timed-out write might be processed twice.

## Limit concurrent attempts

`RequestConcurrencyLimiter` is an actor-backed `NetworkExecutionControlling` implementation. It limits simultaneous transport attempts; retries and one-time authentication replays count as attempts too.

```swift
let executionController: (any NetworkExecutionControlling)? =
    RequestConcurrencyLimiter(maximumConcurrentRequests: 6)
```

Put the controller on the client. Choose a limit from measured backend and product behavior rather than a large default. It is most useful for screens that fan out to many endpoints, pagination, and recovery from flaky connectivity.

## Circuit breakers

A circuit breaker stops repeatedly sending requests to an unhealthy backend route. It begins closed, opens after consecutive failures, rejects attempts during `resetTimeout`, then permits one half-open probe. A successful probe closes the circuit; a failed probe opens it again.

Use `RouteCircuitBreakingTransport` for most Apps. It uses a separate breaker per method/host/port/path, so one broken endpoint does not block healthy routes.

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

When used with caching, place `CachingTransport` outside the breaker. A cache hit then remains available while the upstream route recovers. Inspect `await circuits.snapshots()` for route-level state in diagnostics.

## Expected UI behavior

- Retry transient failures in the background only within a short, bounded policy.
- Show a normal error state for exhausted retries.
- Treat `CircuitOpenError` as a fast, temporary-unavailable result; do not immediately retry from the UI.
- Use cached content only when the product permits it, and make offline/stale state visible when needed.
