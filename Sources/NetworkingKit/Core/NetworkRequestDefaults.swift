//
//  NetworkRequestDefaults.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

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

private func performRequest<Request: NetworkRequest>(_ request: Request) async throws -> Request.Response {
    var urlRequest = try request.buildURLRequest()
    do { for interceptor in request.client.interceptors { urlRequest = try await interceptor.adapt(urlRequest) } }
    catch { throw NetworkError.interceptorFailed(message: error.localizedDescription) }

    let requestID = urlRequest.value(forHTTPHeaderField: "X-Request-ID") ?? UUID().uuidString
    let context = NetworkRequestContext(id: requestID, method: request.method, url: urlRequest.url ?? request.client.baseURL)
    let startedAt = Date()
    await notify(.started(context), for: request.client)
    if let controller = request.client.executionController { await controller.acquire() }

    do {
        let result = try await executeAdaptedRequest(request, urlRequest: urlRequest)
        if let controller = request.client.executionController { await controller.release() }
        await notify(
            .finished(context, NetworkRequestOutcome(statusCode: result.statusCode, duration: Date().timeIntervalSince(startedAt), error: nil)),
            for: request.client
        )
        return result.response
    } catch let error as NetworkError {
        if let controller = request.client.executionController { await controller.release() }
        await notify(
            .finished(context, NetworkRequestOutcome(statusCode: error.statusCode, duration: Date().timeIntervalSince(startedAt), error: error)),
            for: request.client
        )
        throw error
    } catch {
        if let controller = request.client.executionController { await controller.release() }
        let networkError = NetworkError.transport(message: error.localizedDescription)
        await notify(
            .finished(context, NetworkRequestOutcome(statusCode: nil, duration: Date().timeIntervalSince(startedAt), error: networkError)),
            for: request.client
        )
        throw networkError
    }
}

private func notify(_ event: NetworkEvent, for client: any NetworkClient) async {
    for observer in client.observers { await observer.record(event) }
}

private func executeAdaptedRequest<Request: NetworkRequest>(
    _ request: Request,
    urlRequest: URLRequest
) async throws -> (response: Request.Response, statusCode: Int?) {

    let data: Data
    let response: URLResponse
    do { (data, response) = try await request.client.transport.send(urlRequest) }
    catch is CancellationError { throw NetworkError.cancelled }
    catch let error as URLError where error.code == .cancelled { throw NetworkError.cancelled }
    catch { throw NetworkError.transport(message: error.localizedDescription) }

    let transformedData: Data
    do {
        var currentData = data
        for interceptor in request.client.interceptors.reversed() {
            currentData = try await interceptor.transform(response: response, data: currentData)
        }
        transformedData = currentData
    }
    catch { throw NetworkError.interceptorFailed(message: error.localizedDescription) }
    guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.nonHTTPResponse }
    guard NetworkConstants.HTTPStatus.successRange.contains(httpResponse.statusCode) else {
        let headers: [String: String] = Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { element -> (String, String)? in
            guard let key = element.key as? String else { return nil }
            return (key, String(describing: element.value))
        })
        if httpResponse.statusCode == NetworkConstants.HTTPStatus.unauthorized { throw NetworkError.unauthorized(headers: headers, body: transformedData) }
        throw NetworkError.http(statusCode: httpResponse.statusCode, headers: headers, body: transformedData)
    }
    guard !transformedData.isEmpty else {
        guard Request.Response.self == EmptyResponse.self else { throw NetworkError.emptyResponse }
        return (EmptyResponse() as! Request.Response, httpResponse.statusCode)
    }
    do { return (try request.client.makeDecoder().decode(Request.Response.self, from: transformedData), httpResponse.statusCode) }
    catch { throw NetworkError.decodingFailed(message: error.localizedDescription) }
}

public extension NetworkRequest {
    var headers: [String: String]? { nil }
    var timeoutInterval: TimeInterval { client.configuration.timeoutInterval }

    func buildURLRequest() throws -> URLRequest {
        guard var components = URLComponents(url: client.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw NetworkError.invalidURL }
        if let rest = self as? any RestfulRequest, let items = rest.queryItems, !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let rest = self as? any RestfulRequest, let body = rest.body {
            do { request.httpBody = try client.makeEncoder().encode(body) }
            catch { throw NetworkError.encodingFailed(message: error.localizedDescription) }
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue(rest.contentType ?? "application/json", forHTTPHeaderField: "Content-Type") }
        } else if let gql = self as? any GraphQLRequest {
            do { request.httpBody = try client.makeEncoder().encode(GraphQLBody(query: gql.query, variables: gql.variables, operationName: gql.operationName)) }
            catch { throw NetworkError.encodingFailed(message: error.localizedDescription) }
        }
        return request
    }

    func execute() async throws -> Response {
        let retryPolicy = client.configuration.retryPolicy
        var hasRefreshedCredentials = false
        var attempt = NetworkConstants.Retry.firstAttempt
        while attempt <= retryPolicy.maxAttempts {
            do { return try await performRequest(self) }
            catch let error as NetworkError {
                if case .unauthorized = error,
                   !hasRefreshedCredentials,
                   let authentication = client.authentication {
                    hasRefreshedCredentials = true
                    do {
                        guard try await authentication.refreshCredentials() else {
                            throw NetworkError.authenticationRefreshFailed(message: "No refreshed access token was returned")
                        }
                        continue
                    } catch let error as NetworkError {
                        throw error
                    } catch {
                        throw NetworkError.authenticationRefreshFailed(message: error.localizedDescription)
                    }
                }
                guard attempt < retryPolicy.maxAttempts, retryPolicy.shouldRetry(error, method: method) else { throw error }
                do { try await Task.sleep(nanoseconds: retryPolicy.delayNanoseconds(for: error, after: attempt)) }
                catch { throw NetworkError.cancelled }
                attempt += 1
            }
        }
        throw NetworkError.invalidRequest
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
