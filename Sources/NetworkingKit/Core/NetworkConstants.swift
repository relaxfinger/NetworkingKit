//
//  NetworkConstants.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Default policies and HTTP semantic constants used by NetworkingKit.
///
/// Apps can override these defaults through `NetworkClient`, `RetryPolicy`, or an individual request.
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
        public static let defaultMaximumDelay: TimeInterval = 30
        public static let defaultJitterRatio = 0.2
        public static let firstAttempt = 1
        public static let nanosecondsPerSecond = 1_000_000_000.0
    }

    public enum Logging {
        public static let defaultMaxBodyLength = 1_024
        public static let minimumBodyLength = 0
    }
}
