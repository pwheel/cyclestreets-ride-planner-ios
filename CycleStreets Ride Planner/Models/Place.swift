//
//  Place.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation
import MapKit

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

extension Place {
    /// Builds a `Place` from a resolved MapKit search result. `mapItem.name`
    /// is usually present for real search results; the fallback only
    /// matters for hand-constructed test fixtures or unusual map items.
    init(mapItem: MKMapItem) {
        id = UUID().uuidString
        let itemName = mapItem.name
        name = (itemName?.isEmpty ?? true) ? "Unknown location" : itemName!
        let nearParts = [mapItem.placemark.locality, mapItem.placemark.administrativeArea].compactMap { $0 }
        near = nearParts.isEmpty ? nil : nearParts.joined(separator: ", ")
        coordinate = Coordinate(
            longitude: mapItem.placemark.coordinate.longitude,
            latitude: mapItem.placemark.coordinate.latitude
        )
    }
}
