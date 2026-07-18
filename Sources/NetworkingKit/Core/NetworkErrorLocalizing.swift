//
//  NetworkErrorLocalizing.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Converts a `NetworkError` into a user-facing message for a specific locale.
///
/// Apps can provide an implementation backed by their own localization resources and product terminology.
public protocol NetworkErrorLocalizing: Sendable {
    /// Returns a localized, user-facing message for an error.
    func message(for error: NetworkError, locale: Locale) -> String
}

/// The default English localizer for `NetworkError`.
public struct DefaultNetworkErrorLocalizer: NetworkErrorLocalizing {
    public init() {}

    public func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .invalidURL: return "Invalid URL"
        case .invalidRequest: return "Invalid request"
        case .nonHTTPResponse: return "The server did not return an HTTP response"
        case let .http(statusCode, _, _): return "The server returned HTTP status \(statusCode)"
        case .unauthorized: return "Unauthorized. Please sign in again"
        case let .authenticationRefreshFailed(message): return "Authentication refresh failed: \(message)"
        case .emptyResponse: return "The server returned an empty response"
        case let .decodingFailed(message): return "Response decoding failed: \(message)"
        case let .encodingFailed(message): return "Request encoding failed: \(message)"
        case let .interceptorFailed(message): return "Network interceptor failed: \(message)"
        case let .transport(message): return "Network transport failed: \(message)"
        case .cancelled: return "Request cancelled"
        }
    }
}
