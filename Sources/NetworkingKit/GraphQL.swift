import Foundation

/// A typed GraphQL operation. `variables` may be any `Encodable & Sendable` value.
public struct GraphQLOperation<Variables: Encodable & Sendable>: Sendable {
    public let query: String
    public let variables: Variables
    public let operationName: String?
    public init(query: String, variables: Variables, operationName: String? = nil) {
        self.query = query; self.variables = variables; self.operationName = operationName
    }
}

public struct GraphQLError: Decodable, Sendable, Equatable {
    public let message: String
    public let path: [String]?
}

public struct GraphQLResponse<DataType: Decodable & Sendable>: Decodable, Sendable {
    public let data: DataType?
    public let errors: [GraphQLError]?
}

private struct GraphQLPayload<Variables: Encodable & Sendable>: Encodable, Sendable {
    let query: String
    let variables: Variables
    let operationName: String?
}

public extension APIClient {
    /// Executes a GraphQL query or mutation against `path` (usually `"graphql"`).
    func graphql<DataType: Decodable & Sendable, Variables: Encodable & Sendable>(
        _ operation: GraphQLOperation<Variables>, path: String = "graphql"
    ) async throws -> GraphQLResponse<DataType> {
        let request = try APIRequest.json(path, body: GraphQLPayload(query: operation.query, variables: operation.variables, operationName: operation.operationName))
        return try await send(request)
    }
}
