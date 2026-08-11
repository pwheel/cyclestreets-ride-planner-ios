//
//  PhotonEndpointTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import CoreLocation
@testable import CycleStreets_Ride_Planner

struct PhotonEndpointTests {

    @Test func searchBuildsCorrectURLWithoutBias() throws {
        let url = try PhotonEndpoint.search(query: "Cambridge", near: nil)
        #expect(url.host == "photon.komoot.io")
        // NOTE: `url.path` (no-arg) strips the trailing slash on this
        // toolchain's Foundation (verified via a standalone repro: it
        // returns "/api" even though `absoluteString`/`URLComponents.path`
        // both correctly retain "/api/", and the actual request URL is
        // correct). `path(percentEncoded:)` doesn't lose it, so use that.
        #expect(url.path(percentEncoded: false) == "/api/")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["q"] == "Cambridge")
        #expect(items["limit"] == "6")
        #expect(items["lat"] == nil)
        #expect(items["lon"] == nil)
    }

    @Test func searchBuildsCorrectURLWithBias() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
        let url = try PhotonEndpoint.search(query: "Cambridge", near: coordinate)
        #expect(url.absoluteString.contains("lat=52.2053"))
        #expect(url.absoluteString.contains("lon=0.1218"))
    }
}
