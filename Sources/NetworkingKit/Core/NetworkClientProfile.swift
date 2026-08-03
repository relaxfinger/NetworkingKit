//
//  NetworkClientProfile.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// A request behavior profile exposed by one network client.
///
/// Use profiles when one base URL serves request families with different shared
/// headers, authentication, response processing, timeouts, or retry policies.
public struct NetworkClientProfile: Sendable {
    /// The interceptors to run in declaration order.
    public let interceptors: [any NetworkInterceptor]

    /// The credential refresher used to replay one unauthorized request.
    ///
    /// Set this to the same `RefreshingAuthInterceptor` instance included in
    /// `interceptors`. Leave it `nil` for request families that must not refresh credentials.
    public let authentication: (any AuthenticationRefreshing)?

    /// The timeout, retry, and error-localization policy for this profile.
    public let configuration: NetworkConfiguration

    public init(
        interceptors: [any NetworkInterceptor] = [],
        authentication: (any AuthenticationRefreshing)? = nil,
        configuration: NetworkConfiguration = .default
    ) {
        self.interceptors = interceptors
        self.authentication = authentication
        self.configuration = configuration
    }
}
