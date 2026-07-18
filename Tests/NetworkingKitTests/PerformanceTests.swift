//
//  PerformanceTests.swift
//  NetworkingKitTests
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import XCTest
@testable import NetworkingKit

final class PerformanceTests: XCTestCase {
    func testJSONDecoderPerformance() throws {
        let data = Data(#"{"id":"42","name":"Ada"}"#.utf8)
        measure {
            _ = try? JSONDecoder().decode(BenchmarkUser.self, from: data)
        }
    }
}

private struct BenchmarkUser: Decodable { let id: String; let name: String }
