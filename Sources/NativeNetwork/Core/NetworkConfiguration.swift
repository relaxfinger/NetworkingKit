//
//  NetworkConfiguration.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// The default request policy for a `NetworkClient` instance.
///
/// Apps can create independent configurations for production, testing, and staging environments.
public struct NetworkConfiguration: Sendable {
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy

    public init(
        timeoutInterval: TimeInterval = NetworkConstants.Timeout.defaultInterval,
        retryPolicy: RetryPolicy = .none
    ) {
        self.timeoutInterval = max(NetworkConstants.Retry.minimumDelay, timeoutInterval)
        self.retryPolicy = retryPolicy
    }

    public static let `default` = NetworkConfiguration()
}
