import Foundation

/// 网络层统一错误类型。HTTP 错误保留原始 body 与 headers，便于解析服务端错误和请求追踪 ID。
public enum NetworkError: LocalizedError, Sendable {
    case invalidURL
    case invalidRequest
    case nonHTTPResponse
    case http(statusCode: Int, headers: [String: String], body: Data)
    case unauthorized(headers: [String: String], body: Data)
    case emptyResponse
    case decodingFailed(Error)
    case encodingFailed(Error)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .invalidRequest: return "无效的请求"
        case .nonHTTPResponse: return "服务器没有返回 HTTP 响应"
        case let .http(statusCode, _, _): return "服务器响应错误，状态码: \(statusCode)"
        case .unauthorized: return "未授权，请重新登录"
        case .emptyResponse: return "服务器没有返回数据"
        case let .decodingFailed(error): return "数据解析失败: \(error.localizedDescription)"
        case let .encodingFailed(error): return "数据编码失败: \(error.localizedDescription)"
        case let .transport(error): return "网络传输失败: \(error.localizedDescription)"
        }
    }
}
