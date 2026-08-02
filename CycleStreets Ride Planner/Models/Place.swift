//
//  Place.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

struct Place: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let near: String?
    let coordinate: Coordinate

    var displayName: String {
        if let near { return "\(name), \(near)" }
        return name
    }

    var clCoordinate: CLLocationCoordinate2D { coordinate.clCoordinate }

    /// The literal display name `MapViewModel.useCurrentLocation(as:)` gives
    /// the synthesized "Current Location" place — a single source of truth
    /// so the dropdown can detect it (e.g. to avoid offering "Current
    /// Location" for both From and To) without duplicating the string.
    static let currentLocationName = "Current Location"

    var isCurrentLocation: Bool { name == Self.currentLocationName }
}
