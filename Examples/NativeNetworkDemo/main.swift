import Foundation
import NativeNetwork

@main
struct NativeNetworkDemo {
    static func main() async {
        print("NativeNetwork Demo\n")
        await runRESTDemo()
        await runGraphQLDemo()
    }

    private static func runRESTDemo() async {
        print("--- REST / async-await ---")
        let client = DemoClient(baseURL: URL(string: "https://jsonplaceholder.typicode.com")!)
        do {
            let todo = try await TodoRequest(client: client, id: 1).execute()
            print("Todo #\(todo.id): \(todo.title) [completed: \(todo.completed)]")
        } catch {
            print("REST failed: \(error.localizedDescription)")
        }
    }

    private static func runGraphQLDemo() async {
        print("\n--- GraphQL data/errors envelope ---")
        let client = DemoClient(baseURL: URL(string: "https://rickandmortyapi.com")!)
        do {
            let response = try await CharacterRequest(client: client, id: "1").execute()
            if let character = response.data?.character {
                print("Character: \(character.name) (\(character.species))")
            }
            response.errors?.forEach { print("GraphQL error: \($0.message)") }
        } catch {
            print("GraphQL failed: \(error.localizedDescription)")
        }
    }
}

private final class DemoClient: NetworkClient, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession = .shared
    let interceptors: [any NetworkInterceptor] = [LoggingInterceptor()]
    let retryPolicy = RetryPolicy(maxAttempts: 2)

    init(baseURL: URL) { self.baseURL = baseURL }
}

private struct Todo: Codable, Sendable {
    let id: Int
    let title: String
    let completed: Bool
}

private struct TodoRequest: RestfulRequest {
    typealias Response = Todo
    let client: any NetworkClient
    let id: Int
    var path: String { "todos/\(id)" }
    var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

private struct CharacterPayload: Codable, Sendable {
    struct Character: Codable, Sendable { let name: String; let species: String }
    let character: Character?
}

private struct CharacterRequest: GraphQLRequest {
    typealias Response = GraphQLResponse<CharacterPayload>
    let client: any NetworkClient
    let id: String
    let query = "query Character($id: ID!) { character(id: $id) { name species } }"
    var variables: [String: AnyEncodable]? { ["id": AnyEncodable(id)] }
}
