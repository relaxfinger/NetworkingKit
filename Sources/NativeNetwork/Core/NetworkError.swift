//
//  NetworkError.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// The unified error type for network operations.
///
/// HTTP errors retain the original body and headers for server-error parsing and request-trace correlation.
public enum NetworkError: LocalizedError, Sendable {
    case invalidURL
    case invalidRequest
    case nonHTTPResponse
    case http(statusCode: Int, headers: [String: String], body: Data)
    case unauthorized(headers: [String: String], body: Data)
    case emptyResponse
    case decodingFailed(message: String)
    case encodingFailed(message: String)
    case interceptorFailed(message: String)
    case transport(message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidRequest: return "Invalid request"
        case .nonHTTPResponse: return "The server did not return an HTTP response"
        case let .http(statusCode, _, _): return "The server returned HTTP status \(statusCode)"
        case .unauthorized: return "Unauthorized. Please sign in again"
        case .emptyResponse: return "The server returned an empty response"
        case let .decodingFailed(message): return "Response decoding failed: \(message)"
        case let .encodingFailed(message): return "Request encoding failed: \(message)"
        case let .interceptorFailed(message): return "Network interceptor failed: \(message)"
        case let .transport(message): return "Network transport failed: \(message)"
        case .cancelled: return "Request cancelled"
        }
    }
}
