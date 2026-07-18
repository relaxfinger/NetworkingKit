//
//  AnyEncodable.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// A type-erased `Encodable` wrapper for GraphQL variables and other heterogeneous payloads.
public struct AnyEncodable: Encodable, Sendable {
    private let encodeClosure: @Sendable (Encoder) throws -> Void
    
    public init<T: Encodable & Sendable>(_ value: T) {
        self.encodeClosure = { encoder in
            try value.encode(to: encoder)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
