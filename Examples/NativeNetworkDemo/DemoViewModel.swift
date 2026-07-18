import Foundation
import NativeNetwork

@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var restCharacter: RESTCharacter?
    @Published private(set) var graphQLCharacter: GraphQLCharacterPayload.Character?
    @Published private(set) var message = "Choose a request to begin"
    @Published private(set) var isLoading = false

    func loadRESTCharacter() {
        Task {
            beginLoading()
            do {
                restCharacter = try await GetCharacterRequest(id: DemoConstants.characterID).execute()
                graphQLCharacter = nil
            } catch { message = error.localizedDescription }
            isLoading = false
        }
    }

    func loadGraphQLCharacter() {
        Task {
            beginLoading()
            do {
                let response = try await FetchCharacterProfileRequest(id: DemoConstants.characterID).execute()
                graphQLCharacter = response.data?.character
                restCharacter = nil
                if let error = response.errors?.first { message = error.message }
            } catch { message = error.localizedDescription }
            isLoading = false
        }
    }

    private func beginLoading() { message = "Loading…"; isLoading = true }
}

private enum DemoConstants {
    static let characterID = "1"
    static let retryAttempts = 2
    static let requestTimeout: TimeInterval = 15
}

// MARK: - App networking layer

final class AppNetworkClient: NetworkClient, @unchecked Sendable {
    static let shared = AppNetworkClient()

    let baseURL = URL(string: "https://rickandmortyapi.com")!
    let session: URLSession
    let interceptors: [any NetworkInterceptor] = []
    let retryPolicy = RetryPolicy(maxAttempts: DemoConstants.retryAttempts)

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = DemoConstants.requestTimeout
        self.session = URLSession(configuration: configuration)
    }
}

/// 业务请求的 App 基类：统一注入 AppNetworkClient，避免重复传 client。
class AppRequest<T: Decodable & Sendable>: NetworkRequest, @unchecked Sendable {
    typealias Response = T
    let client: any NetworkClient = AppNetworkClient.shared
    var path: String { "" }
    var method: HTTPMethod { .get }
    var headers: [String: String]? { nil }
}

// MARK: - REST

struct RESTCharacter: Codable, Sendable {
    let id: Int
    let name: String
    let species: String
    let status: String
}

final class GetCharacterRequest: AppRequest<RESTCharacter>, RestfulRequest, @unchecked Sendable {
    private let id: String

    init(id: String) { self.id = id }
    override var path: String { "/api/character/\(id)" }
    override var method: HTTPMethod { .get }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var contentType: String? { nil }
}

// MARK: - GraphQL

struct GraphQLCharacterPayload: Codable, Sendable {
    struct Character: Codable, Sendable { let name: String; let species: String; let status: String }
    let character: Character?
}

final class FetchCharacterProfileRequest: AppRequest<GraphQLResponse<GraphQLCharacterPayload>>, GraphQLRequest, @unchecked Sendable {
    private let id: String

    init(id: String) { self.id = id }
    override var path: String { "/graphql" }
    override var method: HTTPMethod { .post }
    override var headers: [String: String]? { ["Accept": "application/json", "Content-Type": "application/json"] }
    var query: String { "query Character($id: ID!) { character(id: $id) { name species status } }" }
    var variables: [String: AnyEncodable]? { ["id": AnyEncodable(id)] }
}
