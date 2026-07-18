//
//  RestfulRequest.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Describes a RESTful network request.
public protocol RestfulRequest: NetworkRequest {
    /// The URL query items to append to the request URL.
    var queryItems: [URLQueryItem]? { get }
    
    /// The value to encode as the request body.
    var body: (any Encodable & Sendable)? { get }
    
    /// The request content type. Defaults to `application/json`.
    var contentType: String? { get }
}
