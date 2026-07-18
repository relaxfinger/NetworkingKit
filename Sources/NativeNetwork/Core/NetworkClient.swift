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
    
    /// 请求 body 的 JSON 编码器。可按项目配置日期、key 策略等。
    var encoder: JSONEncoder { get }
    
    /// 响应 JSON 解码器。可按项目配置日期、key 策略等。
    var decoder: JSONDecoder { get }
    
    /// 临时服务故障的重试策略。默认不重试。
    var retryPolicy: RetryPolicy { get }
}

public extension NetworkClient {
    var encoder: JSONEncoder { JSONEncoder() }
    var decoder: JSONDecoder { JSONDecoder() }
    var retryPolicy: RetryPolicy { .none }
}
