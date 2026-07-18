import Foundation
@preconcurrency import Combine

private struct GraphQLBody: Encodable, Sendable {
    let query: String
    let variables: [String: AnyEncodable]?
    let operationName: String?
}

private final class CombinePromiseBox<Output>: @unchecked Sendable {
    let fulfill: (Result<Output, NetworkError>) -> Void
    init(_ fulfill: @escaping (Result<Output, NetworkError>) -> Void) { self.fulfill = fulfill }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    func set(_ task: Task<Void, Never>) { lock.lock(); self.task = task; lock.unlock() }
    func cancel() { lock.lock(); task?.cancel(); lock.unlock() }
}

public extension NetworkRequest {
    var headers: [String: String]? { nil }
    var timeoutInterval: TimeInterval { 30 }

    func buildURLRequest() throws -> URLRequest {
        guard var components = URLComponents(url: client.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw NetworkError.invalidURL }
        if let rest = self as? any RestfulRequest, let items = rest.queryItems, !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let rest = self as? any RestfulRequest, let body = rest.body {
            do { request.httpBody = try JSONEncoder().encode(body) }
            catch { throw NetworkError.encodingFailed(message: error.localizedDescription) }
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue(rest.contentType ?? "application/json", forHTTPHeaderField: "Content-Type") }
        } else if let gql = self as? any GraphQLRequest {
            do { request.httpBody = try JSONEncoder().encode(GraphQLBody(query: gql.query, variables: gql.variables, operationName: gql.operationName)) }
            catch { throw NetworkError.encodingFailed(message: error.localizedDescription) }
        }
        return request
    }

    func execute() async throws -> Response {
        var urlRequest = try buildURLRequest()
        do { for interceptor in client.interceptors { urlRequest = try await interceptor.adapt(urlRequest) } }
        catch { throw NetworkError.interceptorFailed(message: error.localizedDescription) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await client.session.data(for: urlRequest) }
        catch is CancellationError { throw NetworkError.cancelled }
        catch let error as URLError where error.code == .cancelled { throw NetworkError.cancelled }
        catch { throw NetworkError.transport(message: error.localizedDescription) }
        do { for interceptor in client.interceptors { try await interceptor.intercept(response: response, data: data) } }
        catch { throw NetworkError.interceptorFailed(message: error.localizedDescription) }
        guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.nonHTTPResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            let headers: [String: String] = Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { element -> (String, String)? in
                guard let key = element.key as? String else { return nil }
                return (key, String(describing: element.value))
            })
            if httpResponse.statusCode == 401 { throw NetworkError.unauthorized(headers: headers, body: data) }
            throw NetworkError.http(statusCode: httpResponse.statusCode, headers: headers, body: data)
        }
        guard !data.isEmpty else { throw NetworkError.emptyResponse }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw NetworkError.decodingFailed(message: error.localizedDescription) }
    }

    /// Combine bridge. Work starts on subscription and cancellation propagates to URLSession.
    func executePublisher() -> AnyPublisher<Response, NetworkError> {
        Deferred { [request = self] in
            let taskBox = TaskBox()
            return Future<Response, NetworkError> { promise in
                let promiseBox = CombinePromiseBox(promise)
                taskBox.set(Task {
                    do { promiseBox.fulfill(.success(try await request.execute())) }
                    catch let error as NetworkError { promiseBox.fulfill(.failure(error)) }
                    catch { promiseBox.fulfill(.failure(.transport(message: error.localizedDescription))) }
                })
            }
            .handleEvents(receiveCancel: { taskBox.cancel() })
            .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}
