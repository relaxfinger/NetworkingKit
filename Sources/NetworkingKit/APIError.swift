import Foundation

/// Errors produced while preparing, sending, or decoding a network request.
public enum APIError: Error, Sendable, Equatable {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(code: Int, data: Data)
    case decoding(message: String)
    case encoding(message: String)
    case transport(message: String)
    case cancelled
}
