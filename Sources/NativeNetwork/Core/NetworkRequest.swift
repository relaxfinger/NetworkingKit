//
//  NetworkRequest.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
@preconcurrency import Combine

/// The base protocol for all network requests.
public protocol NetworkRequest: Sendable {
    associatedtype Response: Decodable & Sendable
    
    /// The client supplied by an app-specific base type or concrete request.
    var client: any NetworkClient { get }
    
    /// The request path relative to the client's base URL.
    var path: String { get }
    
    /// The HTTP method to use for the request.
    var method: HTTPMethod { get }
    
    /// Additional HTTP headers for the request.
    var headers: [String: String]? { get }
    
    /// The request timeout in seconds. Defaults to the client's configured timeout.
    var timeoutInterval: TimeInterval { get }
    
    // MARK: - Execution
    func execute() async throws -> Response
    func executePublisher() -> AnyPublisher<Response, NetworkError>
}
