import Foundation

/// 支持任意 Encodable 类型的包装，方便 GraphQL variables 使用
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
