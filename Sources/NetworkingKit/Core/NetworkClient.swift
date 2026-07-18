//
//  NetworkClient.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Describes the network dependencies and defaults owned by an app.
///
/// Implement this protocol to configure the base URL, transport, and shared interceptors.
public protocol NetworkClient: AnyObject, Sendable {
    /// The base URL used to resolve request paths.
    var baseURL: URL { get }
    
    /// The session used to perform requests. Its configuration can include custom certificate validation.
    var session: URLSession { get }

    /// The transport used to send requests.
    ///
    /// The default implementation uses `session`. Override it for deterministic tests or a custom transport.
    var transport: any NetworkTransport { get }
    
    /// The interceptors to run in declaration order.
    var interceptors: [any NetworkInterceptor] { get }
    
    /// Creates a JSON encoder for one request body.
    ///
    /// Return a configured encoder when the app uses custom date or key strategies.
    func makeEncoder() -> JSONEncoder
    
    /// Creates a JSON decoder for one response body.
    ///
    /// Return a configured decoder when the app uses custom date or key strategies.
    func makeDecoder() -> JSONDecoder
    
    /// The default network policy for this client instance.
    var configuration: NetworkConfiguration { get }

    /// The legacy retry-policy entry point.
    ///
    /// New code should configure retries through `configuration.retryPolicy`.
    var retryPolicy: RetryPolicy { get }
}

public extension NetworkClient {
    var transport: any NetworkTransport { URLSessionTransport(session: session) }
    func makeEncoder() -> JSONEncoder { JSONEncoder() }
    func makeDecoder() -> JSONDecoder { JSONDecoder() }
    var retryPolicy: RetryPolicy { .none }
    var configuration: NetworkConfiguration { NetworkConfiguration(retryPolicy: retryPolicy) }
}
