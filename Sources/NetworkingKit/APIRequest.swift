import Foundation

/// A value describing one REST request. Build it with the convenient static helpers.
public struct APIRequest: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data?

    public init(path: String, method: HTTPMethod = .get, query: [String: String] = [:], headers: [String: String] = [:], body: Data? = nil) {
        self.path = path; self.method = method; self.query = query; self.headers = headers; self.body = body
    }

    public static func get(_ path: String, query: [String: String] = [:]) -> Self { .init(path: path, query: query) }
    public static func delete(_ path: String) -> Self { .init(path: path, method: .delete) }

    /// Encodes an `Encodable` body as JSON.
    public static func json<Body: Encodable & Sendable>(_ path: String, method: HTTPMethod = .post, body: Body, encoder: JSONEncoder = .init()) throws -> Self {
        do { return .init(path: path, method: method, headers: ["Content-Type": "application/json"], body: try encoder.encode(body)) }
        catch { throw APIError.encoding(message: error.localizedDescription) }
    }
}
