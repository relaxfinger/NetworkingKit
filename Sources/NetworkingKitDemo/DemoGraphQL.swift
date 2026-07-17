import NetworkingKit

/// Copy this pattern when connecting the demo to a GraphQL server.
enum DemoGraphQL {
    struct Variables: Codable, Sendable { let id: String }
    struct UserQuery: Codable, Sendable {
        struct User: Codable, Sendable { let id: String; let name: String }
        let user: User?
    }

    static func loadUser(using api: APIClient) async throws -> UserQuery.User? {
        let operation = GraphQLOperation(
            query: "query User($id: ID!) { user(id: $id) { id name } }",
            variables: Variables(id: "1")
        )
        let response: GraphQLResponse<UserQuery> = try await api.graphql(operation)
        return response.data?.user
    }
}
