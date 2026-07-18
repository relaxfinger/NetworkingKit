import Foundation

/// 网络层统一错误类型
public enum NetworkError: LocalizedError, Sendable {
    case invalidURL
    case invalidRequest
    case badServerResponse(statusCode: Int)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case noData
    case unauthorized
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidRequest:
            return "无效的请求"
        case .badServerResponse(let code):
            return "服务器响应错误，状态码: \(code)"
        case .decodingFailed(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "数据编码失败: \(error.localizedDescription)"
        case .noData:
            return "没有返回数据"
        case .unauthorized:
            return "未授权，请重新登录"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}
