//
//  NetworkConfiguration.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// The default request policy for a `NetworkClient` instance.
///
/// Apps can create independent configurations for production, testing, and staging environments.
public struct NetworkConfiguration: Sendable {
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy
    public let errorLocalizer: any NetworkErrorLocalizing

    public init(
        timeoutInterval: TimeInterval = NetworkConstants.Timeout.defaultInterval,
        retryPolicy: RetryPolicy = .none,
        errorLocalizer: any NetworkErrorLocalizing = DefaultNetworkErrorLocalizer()
    ) {
        self.timeoutInterval = max(NetworkConstants.Retry.minimumDelay, timeoutInterval)
        self.retryPolicy = retryPolicy
        self.errorLocalizer = errorLocalizer
    }

    public static let `default` = NetworkConfiguration()
}
