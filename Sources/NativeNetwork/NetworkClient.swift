import Foundation

/// 网络客户端协议
/// App 中实现此协议，配置 baseURL、Session、证书校验、公共 Interceptor 等
public protocol NetworkClient: AnyObject, Sendable {
    /// 基础 URL
    var baseURL: URL { get }
    
    /// URLSession 实例（可自定义配置，包括证书校验）
    var session: URLSession { get }
    
    /// 拦截器列表（按顺序执行）
    var interceptors: [any NetworkInterceptor] { get }
}
