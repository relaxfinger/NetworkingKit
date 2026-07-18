import Foundation

/// GraphQL 请求协议
public protocol GraphQLRequest: NetworkRequest {
    /// GraphQL 查询语句
    var query: String { get }
    
    /// 变量
    var variables: [String: AnyEncodable]? { get }
    
    /// 操作名称
    var operationName: String? { get }
}

// MARK: - GraphQL 默认实现
public extension GraphQLRequest {
    var path: String { "/graphql" }
    var method: HTTPMethod { .post }
    var headers: [String: String]? { ["Content-Type": "application/json"] }
    var variables: [String: AnyEncodable]? { nil }
    var operationName: String? { nil }
    var timeoutInterval: TimeInterval { 30 }
}
