import Foundation

// MARK: - 常用 Interceptor 示例（可直接使用或参考）

/// 日志拦截器
public final class LoggingInterceptor: NetworkInterceptor, @unchecked Sendable {
    public init() {}
    
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        print("🌐 [Request] \(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            print("Body: \(bodyString)")
        }
        return request
    }
    
    public func intercept(response: URLResponse, data: Data) async throws {
        guard let http = response as? HTTPURLResponse else { return }
        print("✅ [Response] Status: \(http.statusCode) \(http.url?.absoluteString ?? "")")
        
        if let bodyString = String(data: data, encoding: .utf8), bodyString.count < 3000 {
            print("Data: \(bodyString)")
        }
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
