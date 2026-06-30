//
//  APIClientTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
import CoreLocation
@testable import CycleStreets_Ride_Planner

struct APIClientTests {

    @Test func testJourneyPlanBuildsCorrectURL() throws {
        let key = "testkey123"
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        let url  = try Endpoints.journeyPlan(from: from, to: to, plan: .balanced, apiKey: key)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["key"] == key)
        #expect(items["plan"] == "balanced")
        #expect(items["waypoints"]?.contains("0.1132") == true)
    }

    @Test func testGeocodeBuildsCorrectURL() throws {
        let url = try Endpoints.geocode(query: "Cambridge", apiKey: "k")
        #expect(url.absoluteString.contains("Cambridge"))
    }

}
