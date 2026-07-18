//
//  NetworkInterceptor.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// 网络拦截器协议
/// 可用于 Auth、Logging、Retry、Mock 等场景
public protocol NetworkInterceptor: Sendable {
    /// 请求拦截。返回修改后的请求值，避免 async `inout` 跨挂起点。
    func adapt(_ request: URLRequest) async throws -> URLRequest
    
    /// 响应拦截（可处理响应数据或错误）
    func intercept(response: URLResponse, data: Data) async throws
}

// MARK: - 默认空实现
public extension NetworkInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest { request }
    func intercept(response: URLResponse, data: Data) async throws {}
}
