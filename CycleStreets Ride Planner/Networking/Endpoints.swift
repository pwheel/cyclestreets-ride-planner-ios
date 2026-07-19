//
//  Endpoints.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

enum Endpoints {
    private static let base = "https://api.cyclestreets.net/v2"

    /// Journey planning is still on the v1 API (see
    /// https://www.cyclestreets.net/api/v1/journey/) — the v2 `/journey.json`
    /// path used previously does not exist.
    static func journeyPlan(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        plan: RoutePlan,
        apiKey: String
    ) throws -> URL {
        var c = URLComponents(string: "https://www.cyclestreets.net/api/journey.json")!
        // CycleStreets itinerarypoints format: lon,lat|lon,lat
        let itinerarypoints = "\(from.longitude),\(from.latitude)|\(to.longitude),\(to.latitude)"
        c.queryItems = [
            .init(name: "key",             value: apiKey),
            .init(name: "plan",            value: plan.rawValue),
            .init(name: "itinerarypoints", value: itinerarypoints),
            .init(name: "reporterrors",    value: "1"),
            .init(name: "segments",        value: "1"),
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

    /// GPX files are served from the public website URL namespace, not the
    /// JSON API — no key is required. See
    /// https://www.cyclestreets.net/api/v1/journey/#gpxkml
    static func gpxExport(journeyID: Int, plan: RoutePlan) throws -> URL {
        let string = "https://www.cyclestreets.net/journey/\(journeyID)/cyclestreets\(journeyID)\(plan.rawValue).gpx"
        guard let url = URL(string: string) else { throw URLError(.badURL) }
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
