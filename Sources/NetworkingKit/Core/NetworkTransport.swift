//
//  NetworkTransport.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Sends URL requests and returns their response data.
///
/// Provide a custom transport to support deterministic tests, a different networking stack,
/// or app-specific connection behavior without changing request definitions.
public protocol NetworkTransport: Sendable {
    /// Sends a request and returns the received data and URL response.
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

/// The default transport backed by `URLSession`.
public struct URLSessionTransport: NetworkTransport, @unchecked Sendable {
    /// The session that performs requests.
    public let session: URLSession

    /// Creates a URLSession-backed transport.
    public init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
