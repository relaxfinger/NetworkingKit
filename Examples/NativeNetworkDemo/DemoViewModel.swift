import Foundation
import NativeNetwork

@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var todo: Todo?
    @Published private(set) var character: CharacterPayload.Character?
    @Published private(set) var message = "Choose a request to begin"
    @Published private(set) var isLoading = false

    private let restClient = DemoClient(baseURL: URL(string: "https://jsonplaceholder.typicode.com")!)
    private let graphQLClient = DemoClient(baseURL: URL(string: "https://rickandmortyapi.com")!)

    func loadTodo() {
        Task {
            beginLoading()
            do {
                todo = try await TodoRequest(client: restClient, id: 1).execute()
                character = nil
            } catch { message = error.localizedDescription }
            isLoading = false
        }
    }

    func loadCharacter() {
        Task {
            beginLoading()
            do {
                let response = try await CharacterRequest(client: graphQLClient, id: "1").execute()
                character = response.data?.character
                todo = nil
                if let error = response.errors?.first { message = error.message }
            } catch { message = error.localizedDescription }
            isLoading = false
        }
    }

    private func beginLoading() { message = "Loading…"; isLoading = true }
}

private final class DemoClient: NetworkClient, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession = .shared
    let interceptors: [any NetworkInterceptor] = [LoggingInterceptor()]
    let retryPolicy = RetryPolicy(maxAttempts: 2)
    init(baseURL: URL) { self.baseURL = baseURL }
}

struct Todo: Codable, Sendable {
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

struct CharacterPayload: Codable, Sendable {
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
