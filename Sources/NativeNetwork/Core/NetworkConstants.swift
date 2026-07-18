//
//  NetworkConstants.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// NativeNetwork 的默认策略与 HTTP 语义常量。
/// 业务 App 可通过 `NetworkClient`、`RetryPolicy` 或具体 Request 覆盖这些默认值。
public enum NetworkConstants {
    public enum Timeout {
        public static let defaultInterval: TimeInterval = 30
    }

    public enum HTTPStatus {
        public static let successRange = 200...299
        public static let unauthorized = 401
        public static let requestTimeout = 408
        public static let tooManyRequests = 429
        public static let serverErrorRange = 500...599
    }

    public enum Retry {
        public static let minimumAttempts = 1
        public static let minimumMultiplier = 1.0
        public static let minimumDelay: TimeInterval = 0
        public static let defaultInitialDelay: TimeInterval = 0.25
        public static let defaultMultiplier = 2.0
        public static let firstAttempt = 1
        public static let nanosecondsPerSecond = 1_000_000_000.0
    }

    public enum Logging {
        public static let defaultMaxBodyLength = 1_024
        public static let minimumBodyLength = 0
    }
}
