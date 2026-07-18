//
//  NetworkConfiguration.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// 一个 `NetworkClient` 实例的默认请求策略。
/// App 可为生产、测试和预发布环境分别创建不同配置，互不影响。
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
