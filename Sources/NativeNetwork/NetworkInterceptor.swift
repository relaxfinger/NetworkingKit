import Foundation

/// 网络拦截器协议
/// 可用于 Auth、Logging、Retry、Mock 等场景
public protocol NetworkInterceptor: Sendable {
    /// 请求拦截（可修改 URLRequest）
    func intercept(_ request: inout URLRequest) async throws
    
    /// 响应拦截（可处理响应数据或错误）
    func intercept(response: URLResponse, data: Data) async throws
}

// MARK: - 默认空实现
public extension NetworkInterceptor {
    func intercept(_ request: inout URLRequest) async throws {}
    func intercept(response: URLResponse, data: Data) async throws {}
}
