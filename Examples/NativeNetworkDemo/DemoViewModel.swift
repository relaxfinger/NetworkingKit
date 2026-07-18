//
//  DemoViewModel.swift
//  NativeNetworkDemo
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import NativeNetwork

@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var restCharacter: RESTCharacter?
    @Published private(set) var graphQLCharacter: GraphQLCharacterPayload.Character?
    @Published private(set) var message = "Choose a request to begin"
    @Published private(set) var isLoading = false

    var localizedErrorExample: String {
        let error = NetworkError.unauthorized(headers: [:], body: Data())
        return error.localizedDescription(using: AppNetworkClient.shared.configuration.errorLocalizer)
    }

    func loadRESTCharacter() {
        Task {
            beginLoading()
            do {
                restCharacter = try await GetCharacterRequest(id: DemoConstants.characterID).execute()
                graphQLCharacter = nil
            } catch { message = localizedMessage(for: error) }
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
            } catch { message = localizedMessage(for: error) }
            isLoading = false
        }
    }

    private func beginLoading() { message = "Loading…"; isLoading = true }

    private func localizedMessage(for error: Error) -> String {
        guard let networkError = error as? NetworkError else { return error.localizedDescription }
        return networkError.localizedDescription(using: AppNetworkClient.shared.configuration.errorLocalizer)
    }
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
    let configuration = NetworkConfiguration(
        timeoutInterval: DemoConstants.requestTimeout,
        retryPolicy: RetryPolicy(maxAttempts: DemoConstants.retryAttempts),
        errorLocalizer: AppNetworkErrorLocalizer()
    )

    private init() {
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration)
    }
}

struct AppNetworkErrorLocalizer: NetworkErrorLocalizing {
    func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .invalidURL:
            return localized("network.error.invalid_url", locale: locale)
        case .invalidRequest:
            return localized("network.error.invalid_request", locale: locale)
        case .nonHTTPResponse:
            return localized("network.error.non_http_response", locale: locale)
        case let .http(statusCode, _, _):
            return String(format: localized("network.error.http_status", locale: locale), statusCode)
        case .unauthorized:
            return localized("network.error.unauthorized", locale: locale)
        case .emptyResponse:
            return localized("network.error.empty_response", locale: locale)
        case let .decodingFailed(message):
            return String(format: localized("network.error.decoding_failed", locale: locale), message)
        case let .encodingFailed(message):
            return String(format: localized("network.error.encoding_failed", locale: locale), message)
        case let .interceptorFailed(message):
            return String(format: localized("network.error.interceptor_failed", locale: locale), message)
        case let .transport(message):
            return String(format: localized("network.error.transport_failed", locale: locale), message)
        case .cancelled:
            return localized("network.error.cancelled", locale: locale)
        }
    }

    private func localized(_ key: String, locale: Locale) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }
}

/// An app-specific base request that injects `AppNetworkClient` to avoid repeating client setup.
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
