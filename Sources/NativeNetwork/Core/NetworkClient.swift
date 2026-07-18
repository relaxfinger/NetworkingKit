//
//  NetworkClient.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Describes the network dependencies and defaults owned by an app.
///
/// Implement this protocol to configure the base URL, session, certificate validation, and shared interceptors.
public protocol NetworkClient: AnyObject, Sendable {
    /// The base URL used to resolve request paths.
    var baseURL: URL { get }
    
    /// The session used to perform requests. Its configuration can include custom certificate validation.
    var session: URLSession { get }
    
    /// The interceptors to run in declaration order.
    var interceptors: [any NetworkInterceptor] { get }
    
    /// The JSON encoder for request bodies. Configure date and key strategies as needed.
    var encoder: JSONEncoder { get }
    
    /// The JSON decoder for response bodies. Configure date and key strategies as needed.
    var decoder: JSONDecoder { get }
    
    /// The default network policy for this client instance.
    var configuration: NetworkConfiguration { get }

    /// The legacy retry-policy entry point.
    ///
    /// New code should configure retries through `configuration.retryPolicy`.
    var retryPolicy: RetryPolicy { get }
}

public extension NetworkClient {
    var encoder: JSONEncoder { JSONEncoder() }
    var decoder: JSONDecoder { JSONDecoder() }
    var retryPolicy: RetryPolicy { .none }
    var configuration: NetworkConfiguration { NetworkConfiguration(retryPolicy: retryPolicy) }
}
