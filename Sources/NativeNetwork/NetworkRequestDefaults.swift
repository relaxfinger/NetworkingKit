import Foundation
import Combine

// MARK: - NetworkRequest 默认实现
public extension NetworkRequest {
    
    var headers: [String: String]? { nil }
    var timeoutInterval: TimeInterval { 30 }
    
    /// 构建 URLRequest
    func buildURLRequest() throws -> URLRequest {
        guard var urlComponents = URLComponents(url: client.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        
        // 处理 REST Query 参数
        if let rest = self as? any RestfulRequest, let items = rest.queryItems, !items.isEmpty {
            urlComponents.queryItems = items
        }
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval
        
        // 设置 Headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 处理请求体
        if let rest = self as? any RestfulRequest {
            if let body = rest.body {
                do {
                    request.httpBody = try JSONEncoder().encode(body)
                } catch {
                    throw NetworkError.encodingFailed(error)
                }
                
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue(rest.contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        } else if let gql = self as? any GraphQLRequest {
            var bodyDict: [String: Any] = ["query": gql.query]
            
            if let variables = gql.variables {
                let encoder = JSONEncoder()
                let data = try encoder.encode(variables)
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    bodyDict["variables"] = dict
                }
            }
            
            if let operationName = gql.operationName {
                bodyDict["operationName"] = operationName
            }
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            } catch {
                throw NetworkError.encodingFailed(error)
            }
        }
        
        return request
    }
    
    /// Async/Await 执行
    func execute() async throws -> Response {
        var urlRequest = try buildURLRequest()
        
        // 执行请求拦截器
        for interceptor in client.interceptors {
            try await interceptor.intercept(&urlRequest)
        }
        
        let (data, response) = try await client.session.data(for: urlRequest)
        
        // 执行响应拦截器
        for interceptor in client.interceptors {
            try await interceptor.intercept(response: response, data: data)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.badServerResponse(statusCode: -1)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw NetworkError.unauthorized
            }
            throw NetworkError.badServerResponse(statusCode: httpResponse.statusCode)
        }
        
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
    
    /// Combine 执行
    func executePublisher() -> AnyPublisher<Response, Error> {
        Future { promise in
            Task {
                do {
                    let result = try await execute()
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
