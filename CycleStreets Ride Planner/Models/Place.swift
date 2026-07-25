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
}
