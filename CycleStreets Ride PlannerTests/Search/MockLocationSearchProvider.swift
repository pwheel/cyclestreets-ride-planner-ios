//
//  MockLocationSearchProvider.swift
//  CycleStreets Ride PlannerTests
//

import CoreLocation
@testable import CycleStreets_Ride_Planner

final class MockLocationSearchProvider: LocationSearchProviding {
    struct QueryCall {
        let query: String
        let near: CLLocationCoordinate2D?
    }

    private(set) var queriesReceived: [QueryCall] = []
    var resultsToReturn: [Place] = []
    var errorToThrow: Error?
    var delayMilliseconds: UInt64 = 0

    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place] {
        try Task.checkCancellation()
        if delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        try Task.checkCancellation()
        if let errorToThrow { throw errorToThrow }
        queriesReceived.append(QueryCall(query: query, near: coordinate))
        return resultsToReturn
    }
}
