@preconcurrency import Combine
import Foundation

private final class CombinePromiseBox<Output>: @unchecked Sendable {
    let fulfill: (Result<Output, APIError>) -> Void
    init(_ fulfill: @escaping (Result<Output, APIError>) -> Void) { self.fulfill = fulfill }
}

/// A concurrency-safe HTTP client for JSON REST APIs and GraphQL endpoints.
public actor APIClient {
    public let baseURL: URL
    private let session: URLSession
    private let defaultHeaders: [String: String]
    private let interceptors: [any RequestInterceptor]
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared, defaultHeaders: [String: String] = [:], interceptors: [any RequestInterceptor] = [], decoder: JSONDecoder = .init()) {
        self.baseURL = baseURL; self.session = session; self.defaultHeaders = defaultHeaders; self.interceptors = interceptors; self.decoder = decoder
    }

    /// Sends a REST request and decodes its JSON response.
    public func send<Response: Decodable & Sendable>(_ request: APIRequest, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await raw(request)
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(message: error.localizedDescription) }
    }

    /// Sends a request when the server returns no JSON body.
    public func send(_ request: APIRequest) async throws { _ = try await raw(request) }

    /// A Combine bridge for apps that already use publishers.
    public nonisolated func publisher<Response: Decodable & Sendable>(_ request: APIRequest, as type: Response.Type = Response.self) -> AnyPublisher<Response, APIError> {
        Deferred {
            Future { promise in
                let box = CombinePromiseBox(promise)
                Task {
                    do { box.fulfill(.success(try await self.send(request, as: type))) }
                    catch let error as APIError { box.fulfill(.failure(error)) }
                    catch { box.fulfill(.failure(.transport(message: error.localizedDescription))) }
                }
            }
        }.eraseToAnyPublisher()
    }

    private func raw(_ originalRequest: APIRequest) async throws -> Data {
        var request = originalRequest
        for interceptor in interceptors { request = try await interceptor.adapt(request) }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(request.path), resolvingAgainstBaseURL: false) else { throw APIError.invalidURL(request.path) }
        if !request.query.isEmpty { components.queryItems = request.query.map(URLQueryItem.init) }
        guard let url = components.url else { throw APIError.invalidURL(request.path) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        defaultHeaders.merging(request.headers, uniquingKeysWith: { _, new in new }).forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw APIError.httpStatus(code: http.statusCode, data: data) }
            return data
        } catch let error as APIError { throw error }
        catch is CancellationError { throw APIError.cancelled }
        catch { throw APIError.transport(message: error.localizedDescription) }
    }
}
