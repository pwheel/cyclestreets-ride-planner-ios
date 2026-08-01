//
//  APIClientTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
@testable import CycleStreets_Ride_Planner

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
