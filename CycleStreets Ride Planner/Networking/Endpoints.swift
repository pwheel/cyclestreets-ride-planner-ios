//
//  Endpoints.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

enum Endpoints {
    private static let base = "https://api.cyclestreets.net/v2"

    static func journeyPlan(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        plan: RoutePlan,
        apiKey: String
    ) throws -> URL {
        var c = URLComponents(string: "\(base)/journey.json")!
        // CycleStreets waypoints format: lon,lat:lon,lat
        let waypoints = "\(from.longitude),\(from.latitude):\(to.longitude),\(to.latitude)"
        c.queryItems = [
            .init(name: "key",       value: apiKey),
            .init(name: "plan",      value: plan.rawValue),
            .init(name: "waypoints", value: waypoints),
            .init(name: "format",    value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

    static func geocode(query: String, apiKey: String) throws -> URL {
        var c = URLComponents(string: "\(base)/geocoder")!
        c.queryItems = [
            .init(name: "key",     value: apiKey),
            .init(name: "q",       value: query),
            .init(name: "results", value: "6"),
            .init(name: "format",  value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

    static func gpxExport(journeyID: Int, apiKey: String) throws -> URL {
        var c = URLComponents(string: "https://www.cyclestreets.net/api/journey.gpx")!
        c.queryItems = [
            .init(name: "itinerary", value: "\(journeyID)"),
            .init(name: "key",       value: apiKey),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

    static func login(username: String, password: String, apiKey: String) throws -> URL {
        var c = URLComponents(string: "\(base)/user.authenticate")!
        c.queryItems = [
            .init(name: "key",      value: apiKey),
            .init(name: "username", value: username),
            .init(name: "password", value: password),
            .init(name: "format",   value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }
}
