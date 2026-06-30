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
    func downloadGPX(journeyID: Int) async throws -> Data
    func login(username: String, password: String) async throws -> String
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
        return try JSONDecoder().decode(JourneyResponse.self, from: data).journey
    }

    func geocode(query: String) async throws -> [Place] {
        let url = try Endpoints.geocode(query: query, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(PlaceSearchResponse.self, from: data).results.place
    }

    func downloadGPX(journeyID: Int) async throws -> Data {
        let url = try Endpoints.gpxExport(journeyID: journeyID, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return data
    }

    func login(username: String, password: String) async throws -> String {
        let url = try Endpoints.login(username: username, password: password, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        struct AuthResponse: Decodable {
            struct User: Decodable { let token: String }
            let user: User
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data).user.token
    }
}
