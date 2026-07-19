# Interceptors

[简体中文](Interceptors.zh-Hans.md) · [Documentation index](README.md)

An interceptor is a reusable processing point on a client's request path. Use it for behavior that is shared by many endpoints: common headers, request IDs, signatures, authentication, logging, response-envelope conversion, and request/response test behavior. Do not put a business endpoint's path, query, or body in an interceptor; those belong in `RestfulRequest` or `GraphQLRequest`.

## Execution order

For `interceptors: [A, B, C]`:

1. Outgoing `adapt(_:)` runs `A → B → C` before the transport sends a request.
2. Incoming `transform(response:data:)` runs `C → B → A` before HTTP-status validation and decoding.

This reverse response order lets an outer interceptor see the result after inner processing. Throwing from either method becomes `NetworkError.interceptorFailed`.

## Register once on the client

```swift
final class APIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = APIClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession(configuration: .default)

    var interceptors: [any NetworkInterceptor] {
        [
            RequestIDInterceptor(),
            CommonHeadersInterceptor(),
            LoggingInterceptor(logBodies: false) { print($0) }
        ]
    }
}
```

`LoggingInterceptor` defaults to body redaction. Keep body logging disabled in production unless the endpoint's data is explicitly safe to record.

## Example: common headers

```swift
struct CommonHeadersInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue("1.0.0", forHTTPHeaderField: "X-App-Version")
        return request
    }
}
```

This keeps app-wide headers consistent. An endpoint that genuinely needs a different header can still return it through `NetworkRequest.headers`.

## Example: unwrap a shared response envelope

Use a response transform when every endpoint from one backend wraps its JSON in the same outer structure. The transform must validate its own assumptions and return only the bytes that the request's `Response` should decode.

```swift
struct EnvelopeInterceptor: NetworkInterceptor {
    func transform(response: URLResponse, data: Data) async throws -> Data {
        // Decode the App's concrete envelope type, then encode only its payload
        // for request decoding. This placeholder preserves the original response.
        data
    }
}
```

For a heterogeneous envelope, prefer a dedicated concrete response model or a custom `NetworkTransport`; do not introduce unsafe `Any` decoding. The transform hook is best when the envelope has a stable, testable contract.

## Testing guidance

Test each interceptor independently with a `URLRequest` and known response data. Test the complete client order once: headers and authentication should run before the transport; envelope conversion should run before decoding. For fully deterministic endpoint tests, a small `NetworkTransport` stub is usually simpler than an interceptor.
