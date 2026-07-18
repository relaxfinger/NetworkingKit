//
//  GraphQLRequest.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// GraphQL 标准响应 envelope。GraphQL 允许 `data` 与 `errors` 同时存在，调用方可按业务决定是否采用部分数据。
public struct GraphQLResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let data: Payload?
    public let errors: [GraphQLError]?

    public init(data: Payload?, errors: [GraphQLError]?) {
        self.data = data
        self.errors = errors
    }
}

/// GraphQL 服务返回的业务错误。
public struct GraphQLError: Decodable, Sendable, Equatable {
    public let message: String
    public let locations: [Location]?
    public let path: [JSONValue]?
    public let extensions: [String: JSONValue]?

    public struct Location: Decodable, Sendable, Equatable {
        public let line: Int
        public let column: Int
    }
}

/// 可用于 GraphQL error path 与 extensions 的 JSON 值。
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), boolean(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// GraphQL 请求协议。将 Response 声明为 `GraphQLResponse<YourPayload>`。
public protocol GraphQLRequest: NetworkRequest {
    var query: String { get }
    var variables: [String: AnyEncodable]? { get }
    var operationName: String? { get }
}

public extension GraphQLRequest {
    var path: String { "/graphql" }
    var method: HTTPMethod { .post }
    var headers: [String: String]? { ["Accept": "application/json", "Content-Type": "application/json"] }
    var variables: [String: AnyEncodable]? { nil }
    var operationName: String? { nil }
}
