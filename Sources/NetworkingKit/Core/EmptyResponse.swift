//
//  EmptyResponse.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

/// A successful response with no body, such as HTTP 204 No Content.
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}
