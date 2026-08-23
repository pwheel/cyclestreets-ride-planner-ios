//
//  APIClientTests.swift
//  Wheel RoutesTests
//

import Testing
@testable import Wheel_Routes

struct APIKeyTests {

    @Test func testAPIKeyLoadsFromBundle() throws {
        let key = try APIKey.load()
        #expect(!key.isEmpty)
    }

    @Test func testThunderforestAPIKeyLoadsFromBundle() throws {
        let key = try APIKey.loadThunderforestKey()
        #expect(!key.isEmpty)
    }

}
