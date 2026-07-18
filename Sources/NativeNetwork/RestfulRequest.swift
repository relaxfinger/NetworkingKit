import Foundation

/// RESTful 请求协议
public protocol RestfulRequest: NetworkRequest {
    /// Query 参数
    var queryItems: [URLQueryItem]? { get }
    
    /// 请求体
    var body: Encodable? { get }
    
    /// Content-Type（默认为 application/json）
    var contentType: String? { get }
}
