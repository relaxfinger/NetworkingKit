# Changelog

All notable changes to NetworkingKit are documented in this file.

## 2.2.0 - Unreleased

### Added

- Actor-safe access-token refresh with single-flight coordination and one-time unauthorized request replay.
- Vendor-neutral lifecycle observation, request correlation IDs, and actor-backed concurrent-attempt limiting.
- Composable in-memory response caching with cache-first and offline cache-only transport policies.

## 2.0.0 - 2026-07-18

### Added

- `EmptyResponse` for successful endpoints with no response body.
- Safer retry controls: idempotent methods only by default, capped backoff, jitter, and `Retry-After` support.
- `NetworkTransport` and `URLSessionTransport` for deterministic tests and custom transports.
- Response data transformation through `NetworkInterceptor.transform(response:data:)`.
- Structured HTTP failure access through `NetworkError.statusCode`, `responseHeaders`, and `responseBody`.
- CI builds for the Swift package and both iOS and macOS Demo targets.

### Changed

- `NetworkClient.encoder` and `decoder` are replaced by `makeEncoder()` and `makeDecoder()`, creating a codec per operation.
- `NetworkInterceptor.intercept(response:data:)` is replaced by `transform(response:data:) -> Data`.
- Response interceptors execute in reverse declaration order.

### Migration from 1.x

1. Replace stored `encoder` and `decoder` properties with `makeEncoder()` and `makeDecoder()` methods.
2. Rename `intercept(response:data:)` implementations to `transform(response:data:)`, return the original data when no transformation is needed, and return transformed data otherwise.
3. Use `EmptyResponse` for `204 No Content` endpoints.
4. Review retry behavior: `POST` is no longer retried unless it is explicitly included in `retryableMethods`.

## 1.0.2 - 2026-07-18

- Clarified that app-wide headers, authentication, and logging belong in interceptors.

## 1.0.1 - 2026-07-18

- Restored default GraphQL endpoint, method, and headers for app base request types.

## 1.0.0 - 2026-07-18

- Initial public release.
