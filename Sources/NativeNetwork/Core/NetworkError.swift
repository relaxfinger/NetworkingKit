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
