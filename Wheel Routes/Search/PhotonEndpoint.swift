//
//  PhotonEndpoint.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

/// Builds request URLs for Photon's public demo geocoder API
/// (https://photon.komoot.io) — see
/// docs/superpowers/specs/2026-08-08-improve-typeahead-design.md for why
/// this replaced Apple MapKit for search.
enum PhotonEndpoint {
    private static let base = "https://photon.komoot.io/api/"

    /// `near`, when provided, biases (doesn't filter) results toward that
    /// coordinate via Photon's `lat`/`lon` params.
    static func search(query: String, near coordinate: CLLocationCoordinate2D?) throws -> URL {
        var c = URLComponents(string: base)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "6"),
        ]
        if let coordinate {
            items.append(URLQueryItem(name: "lat", value: "\(coordinate.latitude)"))
            items.append(URLQueryItem(name: "lon", value: "\(coordinate.longitude)"))
        }
        c.queryItems = items
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }
}
