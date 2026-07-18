//
//  NetworkError.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
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
    case authenticationRefreshFailed(message: String)
    case emptyResponse
    case decodingFailed(message: String)
    case encodingFailed(message: String)
    case interceptorFailed(message: String)
    case transport(message: String)
    case cancelled

    /// The HTTP status code when the failure came from an HTTP response.
    public var statusCode: Int? {
        switch self {
        case let .http(statusCode, _, _): return statusCode
        case .unauthorized: return NetworkConstants.HTTPStatus.unauthorized
        default: return nil
        }
    }

    /// The HTTP response headers when they are available.
    public var responseHeaders: [String: String]? {
        switch self {
        case let .http(_, headers, _), let .unauthorized(headers, _): return headers
        default: return nil
        }
    }

    /// The raw HTTP response body when it is available.
    ///
    /// Use this for app-specific server error decoding instead of parsing `localizedDescription`.
    public var responseBody: Data? {
        switch self {
        case let .http(_, _, body), let .unauthorized(_, body): return body
        default: return nil
        }
    }

    /// Returns an English fallback description.
    ///
    /// To display an app-localized message, use `localizedDescription(using:locale:)` with the localizer configured on a `NetworkClient`.
    public var errorDescription: String? {
        localizedDescription(using: DefaultNetworkErrorLocalizer())
    }

    /// Returns a localized, user-facing message using the supplied localizer.
    public func localizedDescription(
        using localizer: any NetworkErrorLocalizing,
        locale: Locale = .current
    ) -> String {
        localizer.message(for: self, locale: locale)
    }
}
