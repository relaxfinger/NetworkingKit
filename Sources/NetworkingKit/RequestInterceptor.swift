/// Customize outgoing requests, for example to add an access token.
public protocol RequestInterceptor: Sendable {
    func adapt(_ request: APIRequest) async throws -> APIRequest
}

/// A lightweight interceptor made from an async closure.
public struct ClosureInterceptor: RequestInterceptor {
    private let transform: @Sendable (APIRequest) async throws -> APIRequest
    public init(_ transform: @escaping @Sendable (APIRequest) async throws -> APIRequest) { self.transform = transform }
    public func adapt(_ request: APIRequest) async throws -> APIRequest { try await transform(request) }
}
