import Foundation

// MARK: - 常用 Interceptor 示例（可直接使用或参考）

/// 默认脱敏且不记录 body 的日志拦截器。生产环境应注入项目自己的统一日志系统。
public struct LoggingInterceptor: NetworkInterceptor {
    public var logBodies: Bool
    public var maxBodyLength: Int
    public var redactedHeaders: Set<String>
    private let logger: @Sendable (String) -> Void
    
    public init(
        logBodies: Bool = false,
        maxBodyLength: Int = 1_024,
        redactedHeaders: Set<String> = ["authorization", "cookie", "set-cookie", "x-api-key"],
        logger: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.logBodies = logBodies
        self.maxBodyLength = max(0, maxBodyLength)
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.logger = logger
    }
    
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        let headers = request.allHTTPHeaderFields?.map { key, value in
            "\(key): \(redactedHeaders.contains(key.lowercased()) ? "<redacted>" : value)"
        }.sorted().joined(separator: ", ") ?? ""
        logger("🌐 [Request] \(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "") [\(headers)]")
        log(body: request.httpBody, label: "Request body")
        return request
    }
    
    public func intercept(response: URLResponse, data: Data) async throws {
        guard let http = response as? HTTPURLResponse else { return }
        logger("✅ [Response] Status: \(http.statusCode) \(http.url?.absoluteString ?? "")")
        log(body: data, label: "Response body")
    }
    
    private func log(body: Data?, label: String) {
        guard logBodies, let body, let text = String(data: body, encoding: .utf8) else { return }
        logger("\(label): \(String(text.prefix(maxBodyLength)))")
    }
}

/// 简单 Auth 拦截器示例
public final class AuthInterceptor: NetworkInterceptor, @unchecked Sendable {
    private let tokenProvider: @Sendable () -> String?
    
    public init(tokenProvider: @escaping @Sendable () -> String?) {
        self.tokenProvider = tokenProvider
    }
    
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
