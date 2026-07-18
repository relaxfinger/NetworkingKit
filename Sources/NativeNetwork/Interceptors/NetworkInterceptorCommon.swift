//
//  NetworkInterceptorCommon.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

// MARK: - Common interceptors

/// A logging interceptor that redacts sensitive headers and omits bodies by default.
///
/// Production apps should inject their own unified logging system.
public struct LoggingInterceptor: NetworkInterceptor {
    public var logBodies: Bool
    public var maxBodyLength: Int
    public var redactedHeaders: Set<String>
    private let logger: @Sendable (String) -> Void
    
    public init(
        logBodies: Bool = false,
        maxBodyLength: Int = NetworkConstants.Logging.defaultMaxBodyLength,
        redactedHeaders: Set<String> = ["authorization", "cookie", "set-cookie", "x-api-key"],
        logger: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.logBodies = logBodies
        self.maxBodyLength = max(NetworkConstants.Logging.minimumBodyLength, maxBodyLength)
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
        self.logger = logger
    }
    
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        let headers = request.allHTTPHeaderFields?.map { key, value in
            "\(key): \(redactedHeaders.contains(key.lowercased()) ? "<redacted>" : value)"
        }.sorted().joined(separator: ", ") ?? ""
        logger("🌐 [Request] \(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "") [\(headers)]")
        log(body: request.httpBody, label: "Request body")
        return request
    }
    
    public func intercept(response: URLResponse, data: Data) async throws {
        guard let http = response as? HTTPURLResponse else { return }
        logger("✅ [Response] Status: \(http.statusCode) \(http.url?.absoluteString ?? "")")
        log(body: data, label: "Response body")
    }
    
    private func log(body: Data?, label: String) {
        guard logBodies, let body, let text = String(data: body, encoding: .utf8) else { return }
        logger("\(label): \(String(text.prefix(maxBodyLength)))")
    }
}

/// A simple interceptor that adds a bearer token to outgoing requests.
public final class AuthInterceptor: NetworkInterceptor, @unchecked Sendable {
    private let tokenProvider: @Sendable () -> String?
    
    public init(tokenProvider: @escaping @Sendable () -> String?) {
        self.tokenProvider = tokenProvider
    }
    
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
