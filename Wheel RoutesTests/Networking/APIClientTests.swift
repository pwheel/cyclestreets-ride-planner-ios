//
//  APIClientTests.swift
//  Wheel RoutesTests
//

import Testing
import Foundation
import CoreLocation
@testable import Wheel_Routes

struct APIClientTests {

    @Test func testJourneyPlanBuildsCorrectURL() throws {
        let key = "testkey123"
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        let url  = try Endpoints.journeyPlan(from: from, to: to, plan: .balanced, apiKey: key)
        #expect(url.host == "www.cyclestreets.net")
        #expect(url.path == "/api/journey.json")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["key"] == key)
        #expect(items["plan"] == "balanced")
        #expect(items["itinerarypoints"]?.contains("0.1132") == true)
        #expect(items["reporterrors"] == "1")
        #expect(items["segments"] == "1")
    }

    @Test func testGeocodeBuildsCorrectURL() throws {
        let url = try Endpoints.geocode(query: "Cambridge", apiKey: "k")
        #expect(url.absoluteString.contains("Cambridge"))
    }

    @Test func testGpxExportBuildsCorrectURL() throws {
        let url = try Endpoints.gpxExport(journeyID: 123700734, plan: .quietest)
        #expect(url.absoluteString == "https://www.cyclestreets.net/journey/123700734/cyclestreets123700734quietest.gpx")
    }

    @Test func testJourneyReloadBuildsCorrectURL() throws {
        let key = "testkey123"
        let url = try Endpoints.journeyReload(itinerary: 123700734, plan: .quietest, apiKey: key)
        #expect(url.host == "www.cyclestreets.net")
        #expect(url.path == "/api/journey.json")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["key"] == key)
        #expect(items["plan"] == "quietest")
        #expect(items["itinerary"] == "123700734")
        #expect(items["reporterrors"] == "1")
        #expect(items["segments"] == "1")
    }

}
