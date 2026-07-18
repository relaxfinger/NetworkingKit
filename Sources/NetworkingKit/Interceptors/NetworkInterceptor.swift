//
//  NetworkInterceptor.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Describes an interceptor that can adapt requests and inspect responses.
///
/// Use interceptors for authentication, logging, retries, mocking, and similar cross-cutting concerns.
public protocol NetworkInterceptor: Sendable {
    /// Adapts an outgoing request.
    ///
    /// Returns a new request value to avoid passing `inout` across an asynchronous suspension point.
    func adapt(_ request: URLRequest) async throws -> URLRequest
    
    /// Inspects a response and its data, and can throw an error.
    func intercept(response: URLResponse, data: Data) async throws
}

// MARK: - Default implementations
public extension NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest { request }
    func intercept(response: URLResponse, data: Data) async throws {}
}
