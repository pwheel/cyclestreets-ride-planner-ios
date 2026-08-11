//
//  MockLocationService.swift
//  Wheel RoutesTests
//

import CoreLocation
@testable import Wheel_Routes

final class MockLocationService: LocationServiceProtocol {
    var coordinateToReturn = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
    var errorToThrow: Error?
    var isAuthorized = false

    func currentLocation() async throws -> CLLocationCoordinate2D {
        if let errorToThrow { throw errorToThrow }
        return coordinateToReturn
    }
}
