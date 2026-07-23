# NetworkingKit documentation

[简体中文](README.zh-Hans.md) · [Package README](../README.md)

These guides are the reference for production use. Read them in the order below for a new App, or open a focused guide when adding one capability to an existing client.

| Guide | Use it when you need to… |
| --- | --- |
| [Getting started](GettingStarted.md) | Organize clients by backend, define typed REST/GraphQL requests, or use Combine. |
| [Caching](Caching.md) | Improve perceived performance, control offline behavior, or coordinate HTTP cache headers with a backend. |
| [Interceptors](Interceptors.md) | Add headers, signing, logging, a response envelope, or test-specific request behavior once. |
| [Authentication](Authentication.md) | Attach bearer tokens and refresh an expired token safely after a `401`. |
| [Reliability](Reliability.md) | Configure retries, control request concurrency, or isolate unhealthy backend routes. |
| [Observability](Observability.md) | Add request IDs, OSLog, OpenTelemetry, or aggregate network metrics. |
| [Errors](Errors.md) | Handle stable errors and show App-localized user messages. |
| [Security](Security.md) | Apply certificate or public-key pinning with a safe certificate-rotation plan. |
| [Backend API reference](BackendReferencePlugin.md) | Generate a browsable backend, endpoint, parameter, and configuration reference from an Xcode project. |

## Recommended adoption path

1. Follow **Getting started** to create one client and one REST request.
2. Add **Interceptors** for client-wide headers and logging.
3. Add **Authentication** when the backend uses bearer credentials.
4. Add **Caching** for reusable `GET` data; agree cache semantics with the backend.
5. Add **Reliability** and **Observability** as traffic and operational requirements grow.
6. Use **Security** only when pinning is an explicit security requirement and a rotation process exists.

## Important boundaries

- A `NetworkClient` represents one backend boundary, not necessarily the entire App.
- A request describes an endpoint's path, method, query, body, and response type.
- Interceptors own shared request/response behavior; do not repeat it in every request.
- Transports compose mechanics such as caching and circuit breaking.
- App code owns product decisions such as which data can be stored offline and how errors appear to users.

Every guide uses Swift 6 and the package's minimum platform versions: iOS 17, macOS 14, tvOS 17, and watchOS 10.
