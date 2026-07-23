# Changelog

All notable changes to NetworkingKit are documented in this file.

## 2.4.1 - 2026-07-23

### Fixed

- Support applying `BackendReferencePlugin` to Xcode project targets through `XcodeBuildToolPlugin`.
- Use URL-based plugin APIs to avoid deprecated `Path` API warnings.

## 2.4.0 - 2026-07-23

### Added

- Add `BackendReferencePlugin` and its generator for build-time HTML references of app backend servers, configuration values, feature-grouped endpoints, request parameters, and source locations.
- Add generated backend-reference HTML to the NetworkingKit Demo.

## 2.3.8 - 2026-07-19

### Changed

- Reorganize documentation: keep the READMEs focused on installation and the first request, and add complete English and Simplified Chinese topic guides under `Docs/`.

## 2.3.7 - 2026-07-19

### Changed

- Expand the English and Chinese cache documentation with cache selection, policy behavior, HTTP cache semantics, backend coordination, offline behavior, lifecycle operations, and production scenarios.
- Update the Demo to use a bounded persistent disk cache with an explicit fallback TTL.

## 2.3.6 - 2026-07-19

### Changed

- Replace App-layer request-base class examples with client-constrained request protocols that provide a default shared client and support both structures and classes.

## 2.3.5 - 2026-07-19

### Changed

- Make every App-layer request-base example bind its own concrete client directly, rather than exposing a generic `SharedNetworkClient` constraint.

## 2.3.4 - 2026-07-19

### Added

- Add `SharedNetworkClient` for application clients exposed through a typed shared instance.

### Changed

- Bind `NetworkRequest` to both concrete `Client` and `Response` types, eliminating request-level `any NetworkClient` erasure.
- Update the Demo, tests, and English and Chinese READMEs with an `AppNetworkRequest<ClientType>` base-class pattern.

## 2.3.3 - 2026-07-19

### Changed

- Keep app-level request base classes model-agnostic: concrete REST and GraphQL requests now declare their own `Response` type in the README, Demo, and app-layer example tests.

## 2.3.2 - 2026-07-19

### Added

- Configurable disk-cache capacity, least-recent-access pruning, footprint statistics, and explicit clearing.

## 2.3.1 - 2026-07-19

### Changed

- Correct HTTP cache revalidation by merging `304 Not Modified` metadata with cached headers.
- Store independent `Vary` response variants, bypass request `no-store`, honor `no-cache`, and reject `Vary: *` responses.
- Use SHA-256 disk-cache filenames to avoid URL-derived filename length limits.

## 2.2.10 - 2026-07-18

### Added

- Actor-safe aggregate network metrics with a vendor-neutral observer adapter.

## 2.2.9 - 2026-07-18

### Added

- Public API compatibility fixture and CI job using third-party integration code only.
- URL request construction performance benchmark alongside JSON decoding coverage.

## 2.2.8 - 2026-07-18

### Added

- Route-scoped circuit breakers with half-open recovery probes and state snapshots.

## 2.2.7 - 2026-07-18

### Added

- SHA-256 public-key hash pinning with backup-pin rotation support.

## 2.2.6 - 2026-07-18

### Added

- Complete cache semantics for `no-store`, `Expires`, `Vary`, and LRU access ordering.

## 2.2.5 - 2026-07-18

### Added

- Release build verification, benchmark smoke test, and tag-triggered release automation.

## 2.2.4 - 2026-07-18

### Added

- OSLog observer and an SDK-agnostic OpenTelemetry event bridge.

## 2.2.3 - 2026-07-18

### Added

- Host-scoped certificate pinning and a reusable URLSession trust delegate.

## 2.2.2 - 2026-07-18

### Added

- Circuit-breaking transport to fail fast during repeated upstream failures.

## 2.2.1 - 2026-07-18

### Added

- Actor-safe access-token refresh with single-flight coordination and one-time unauthorized request replay.
- Vendor-neutral lifecycle observation, request correlation IDs, and actor-backed concurrent-attempt limiting.
- Composable in-memory response caching with cache-first and offline cache-only transport policies.
- Persistent disk cache with `Cache-Control` TTL, ETag validation, and `304 Not Modified` reuse.

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
