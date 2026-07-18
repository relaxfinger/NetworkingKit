//
//  RefreshingAuthInterceptor.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Supplies access tokens and refreshes expired credentials.
///
/// An actor is a natural implementation because token storage is mutable and shared by requests.
public protocol AccessTokenProviding: Sendable {
    /// Returns the current access token, if one is available.
    func accessToken() async -> String?

    /// Refreshes the access token and returns the new value.
    func refreshAccessToken() async throws -> String?
}

/// Refreshes credentials after an unauthorized response.
public protocol AuthenticationRefreshing: Sendable {
    /// Refreshes credentials once for concurrent unauthorized requests.
    ///
    /// Returns `true` only when a usable credential is available for request replay.
    func refreshCredentials() async throws -> Bool
}

/// Coordinates a single in-flight credential refresh across concurrent requests.
public actor TokenRefreshCoordinator {
    private var refreshTask: Task<String?, Error>?

    /// Creates a refresh coordinator.
    public init() {}

    /// Returns the result of the current refresh or starts a new one.
    public func refresh(
        using operation: @escaping @Sendable () async throws -> String?
    ) async throws -> String? {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { try await operation() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

/// Adds bearer credentials and safely refreshes them after a `401 Unauthorized` response.
///
/// Register this instance in both `NetworkClient.interceptors` and `NetworkClient.authentication`.
/// NetworkingKit replays an unauthorized request at most once after a successful refresh.
public final class RefreshingAuthInterceptor: NetworkInterceptor, AuthenticationRefreshing, @unchecked Sendable {
    private let provider: any AccessTokenProviding
    private let coordinator: TokenRefreshCoordinator

    /// Creates an authentication interceptor.
    public init(
        provider: any AccessTokenProviding,
        coordinator: TokenRefreshCoordinator = TokenRefreshCoordinator()
    ) {
        self.provider = provider
        self.coordinator = coordinator
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        if let token = await provider.accessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func refreshCredentials() async throws -> Bool {
        let token = try await coordinator.refresh { [provider] in
            try await provider.refreshAccessToken()
        }
        return token?.isEmpty == false
    }
}
