//
//  GraphQLRequest.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// A standard GraphQL response envelope.
///
/// GraphQL permits `data` and `errors` to coexist, allowing callers to decide whether partial data is usable.
public struct GraphQLResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let data: Payload?
    public let errors: [GraphQLError]?

    public init(data: Payload?, errors: [GraphQLError]?) {
        self.data = data
        self.errors = errors
    }
}

/// An application-level error returned by a GraphQL service.
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

/// A JSON value used by GraphQL error paths and extensions.
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

/// Describes a GraphQL request.
///
/// Declare `Response` as `GraphQLResponse<YourPayload>`.
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
