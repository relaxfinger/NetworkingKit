# HTTP caching and offline reads

[简体中文](Caching.zh-Hans.md) · [Documentation index](README.md)

Caching is a user-experience decision. It can make familiar content appear immediately, reduce network and backend load, and provide an intentional offline mode. It is not a replacement for deciding which data is safe to store.

`CachingTransport` stores only successful `GET` responses. Writes always use the upstream transport so an old mutation result is never mistaken for a completed business action.

## Choose storage

| Type | Lifetime | Use it for | Eviction |
| --- | --- | --- | --- |
| `InMemoryResponseCache` | Current process | Small, non-sensitive screen data | Least recently used request keys after `capacity` |
| `DiskResponseCache` | Survives relaunch | Catalogs, articles, reference data, and offline-friendly reads | Least recently accessed files after `maximumSize` bytes |
| `NetworkResponseCaching` | App-defined | Encrypted storage, a database, or a custom invalidation model | App-defined |

Create the cache once and retain it on the client. A cache created inside the `transport` getter is new on every access and cannot preserve entries.

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

## Choose read behavior

| `NetworkCachePolicy` | Behavior | Use it for |
| --- | --- | --- |
| `.networkOnly` | Bypasses a cache read and always contacts the upstream; an eligible success can still update the cache | Pull to refresh, current-state screens, diagnostics |
| `.returnCacheElseLoad` | Returns a fresh entry immediately; a miss, expiry, or `no-cache` entry goes upstream | Default for catalogs, articles, read-only profiles, and configuration |
| `.returnCacheDontLoad` | Never contacts the network; returns a matching entry even when expired, or throws `CacheMissError` | Explicit offline mode |
| `.staleWhileRevalidate(maxStale:)` | Returns a fresh entry normally; returns an eligible stale entry immediately and refreshes it in the background | Fast repeat loads where briefly stale content is acceptable |

`returnCacheElseLoad` does not silently fall back to stale data after a failed revalidation. If the product wants offline data, create an offline client/transport composition using the same cache and `.returnCacheDontLoad`, then present a clear empty-state for `CacheMissError`.

## Override one request

`NetworkRequest.cachePolicy` defaults to `nil`, which keeps the `CachingTransport` default. Override it when one endpoint needs a different behavior without creating another client.

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

Request-level policies apply when the client transport conforms to `RequestCachePolicyTransport`. Both `CachingTransport` and `RequestCoalescingTransport` conform, and a coalescing wrapper forwards the policy to a cache-aware upstream transport.

## Coalesce concurrent reads

`RequestCoalescingTransport` shares one upstream attempt among equivalent concurrent `GET` and `HEAD` requests. Its privacy-safe default key hashes the method, absolute URL, and request headers while excluding request-ID and distributed-tracing headers. Authorization and language variants therefore remain separate.

```swift
let upstream = RequestCoalescingTransport(
    upstream: URLSessionTransport(session: session)
)
let transport = CachingTransport(upstream: upstream, cache: cache)
```

Only in-flight requests are shared; completed responses are not retained by this transport. Compose it with `CachingTransport` for reuse after completion. Supply a custom `keyProvider` only when the App has a well-defined response-variant model.

## Use stale-while-revalidate

`.staleWhileRevalidate(maxStale:)` returns an expired matching entry immediately when it is within the allowed stale window. NetworkingKit then revalidates the entry in an unstructured background task. An ETag is sent as `If-None-Match`, and either a `304` or a new successful response updates the cache for the next read. When no entry exists or it is older than `maxStale`, the caller waits for the upstream response.

Place `RequestCoalescingTransport` directly upstream of the cache to prevent simultaneous stale reads from creating duplicate revalidations. Background revalidation is best-effort and does not replace an explicit `.networkOnly` refresh when the UI must receive the fresh model in the current interaction.

## Coordinate HTTP semantics with the backend

The App chooses storage and read policy; the backend controls freshness. NetworkingKit supports the following semantics:

| Header | Behavior |
| --- | --- |
| `Cache-Control: max-age=300` | Treats the response as fresh for 300 seconds. |
| `Cache-Control: no-cache` | Stores the response but requires revalidation before reuse. |
| `Cache-Control: no-store` | Does not store the response. A request with this directive also skips cache reads. |
| `Expires` | Used when `max-age` is absent. |
| `ETag` | An expired matching entry sends `If-None-Match`; `304 Not Modified` keeps the local body and refreshes headers/expiry. |
| `Vary` | Keeps independent variants for relevant request headers, such as `Accept-Language`. `Vary: *` is never stored. |

When neither `Cache-Control` nor `Expires` exists, `defaultTTL` is used. For a new backend, prefer `Cache-Control: max-age` plus `ETag` on reusable reads.

```text
GET /articles/42 → 200
Cache-Control: max-age=300
ETag: "article-42-v7"

After five minutes:
GET /articles/42
If-None-Match: "article-42-v7"

Unchanged → 304 Not Modified
```

The `304` response avoids downloading the original JSON again while letting the backend remain the source of truth.

## Lifecycle, privacy, and invalidation

Keep authenticated responses in an App-private directory. Clear user-scoped data when a user signs out or switches account.

```swift
let statistics = await cache.statistics()
print("Cache files: \(statistics.entryCount), bytes: \(statistics.totalSize)")

func signOut() async {
    await cache.removeAll()
    // Then clear credentials and user-specific App state.
}
```

The built-in caches expose `removeAll()` intentionally. If a product needs URL- or entity-specific invalidation after writes, implement `NetworkResponseCaching` with the appropriate index and invalidation rules. Do not cache tokens, one-time secrets, payment data, or any data that cannot be safely removed on logout.

## Test cases to cover

- First `GET` stores a successful eligible response.
- A fresh entry does not contact the upstream under `.returnCacheElseLoad`.
- An expired ETag entry sends `If-None-Match` and handles `304`.
- Different `Vary: Accept-Language` values do not share a response.
- Offline mode returns a matching cached value and reports `CacheMissError` otherwise.
- A request-level `.networkOnly` override bypasses a fresh cache and updates it.
- Stale-while-revalidate returns promptly and refreshes the stored response.
- Equivalent concurrent reads share one upstream attempt, while auth/header variants remain separate.
- Logout removes user-scoped persisted entries.
