import XCTest
@testable import NetworkingKit

final class NetworkingKitTests: XCTestCase {
    func testJSONRequestHasBodyAndContentType() throws {
        struct Input: Codable, Sendable { let name: String }
        let request = try APIRequest.json("users", body: Input(name: "Ana"))
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(try JSONDecoder().decode(Input.self, from: try XCTUnwrap(request.body)).name, "Ana")
    }

    func testAPIErrorIsEquatable() {
        XCTAssertEqual(APIError.invalidURL("bad"), .invalidURL("bad"))
    }
}
