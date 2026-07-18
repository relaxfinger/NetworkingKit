import Foundation
import Combine

/// 网络请求基础协议
/// 所有具体请求都应遵循此协议
public protocol NetworkRequest: Sendable {
    associatedtype Response: Decodable
    
    /// 客户端实例（由 App 基类或具体 Request 提供）
    var client: NetworkClient { get }
    
    /// 请求路径（相对于 baseURL）
    var path: String { get }
    
    /// HTTP 方法
    var method: HTTPMethod { get }
    
    /// 自定义请求头
    var headers: [String: String]? { get }
    
    /// 超时时间（秒），默认 30
    var timeoutInterval: TimeInterval { get }
    
    // MARK: - 执行方法
    func execute() async throws -> Response
    func executePublisher() -> AnyPublisher<Response, Error>
}
