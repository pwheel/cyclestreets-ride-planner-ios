//
//  APIClient.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

protocol APIClientProtocol {
    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey
    func geocode(query: String) async throws -> [Place]
    func downloadGPX(journeyID: Int, plan: RoutePlan) async throws -> Data
}

final class APIClient: APIClientProtocol {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey {
        let url = try Endpoints.journeyPlan(from: from, to: to, plan: plan, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return try JourneyPlanDecoder.decode(data, requestedPlan: plan)
    }

    func geocode(query: String) async throws -> [Place] {
        let url = try Endpoints.geocode(query: query, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return try GeocoderDecoder.decode(data)
    }

    func downloadGPX(journeyID: Int, plan: RoutePlan) async throws -> Data {
        let url = try Endpoints.gpxExport(journeyID: journeyID, plan: plan)
        let (data, _) = try await session.data(from: url)
        return data
    }
}
