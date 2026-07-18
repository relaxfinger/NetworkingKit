//
//  RestfulRequest.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// RESTful 请求协议
public protocol RestfulRequest: NetworkRequest {
    /// Query 参数
    var queryItems: [URLQueryItem]? { get }
    
    /// 请求体
    var body: (any Encodable & Sendable)? { get }
    
    /// Content-Type（默认为 application/json）
    var contentType: String? { get }
}
