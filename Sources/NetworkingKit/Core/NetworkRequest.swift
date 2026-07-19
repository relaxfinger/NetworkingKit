//
//  NetworkRequest.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
@preconcurrency import Combine

/// The base protocol for all network requests.
///
/// `Client` keeps a request bound to its owning backend configuration at compile time,
/// while `Response` describes the model decoded from a successful response.
public protocol NetworkRequest<Client, Response>: Sendable {
    associatedtype Client: NetworkClient
    associatedtype Response: Decodable & Sendable
    
    /// The client supplied by an app-specific base type or concrete request.
    var client: Client { get }
    
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
