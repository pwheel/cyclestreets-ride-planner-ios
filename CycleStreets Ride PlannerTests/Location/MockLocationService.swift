//
//  MockLocationService.swift
//  CycleStreets Ride PlannerTests
//

import CoreLocation
@testable import CycleStreets_Ride_Planner

final class MockLocationService: LocationServiceProtocol {
    var coordinateToReturn = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
    var errorToThrow: Error?

    func currentLocation() async throws -> CLLocationCoordinate2D {
        if let errorToThrow { throw errorToThrow }
        return coordinateToReturn
    }
}
