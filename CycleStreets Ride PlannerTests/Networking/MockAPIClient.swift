//
//  MockAPIClient.swift
//  CycleStreets Ride PlannerTests
//

import Foundation
import CoreLocation
@testable import CycleStreets_Ride_Planner

final class MockAPIClient: APIClientProtocol {
    var journeyToReturn: Journey?
    var placesToReturn: [Place] = []
    var gpxDataToReturn = Data("gpx content".utf8)
    var tokenToReturn = "mock_token"
    var shouldThrow: Error?

    private func checkThrow() throws {
        if let e = shouldThrow { throw e }
    }

    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey {
        try checkThrow()
        return journeyToReturn ?? makeJourney()
    }

    func geocode(query: String) async throws -> [Place] {
        try checkThrow()
        return placesToReturn
    }

    func downloadGPX(journeyID: Int, plan: RoutePlan) async throws -> Data {
        try checkThrow()
        return gpxDataToReturn
    }

    func login(username: String, password: String) async throws -> String {
        try checkThrow()
        return tokenToReturn
    }

    // MARK: - Helpers

    func makeJourney(id: Int = 1, plan: RoutePlan = .balanced) -> Journey {
        Journey(
            number: id, plan: plan, lengthMetres: 4200, timeSeconds: 1080,
            segments: [
                Segment(number: 1, name: "High Street", distanceMetres: 450,
                        timeSeconds: 120, turn: "Straight on",
                        points: [
                            Coordinate(longitude: 0.1132, latitude: 52.2054),
                            Coordinate(longitude: 0.1140, latitude: 52.2060),
                        ])
            ]
        )
    }
}
