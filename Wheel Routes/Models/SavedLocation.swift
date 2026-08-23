//
//  SavedLocation.swift
//  Wheel Routes
//

import Foundation

struct SavedLocation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let coordinate: Coordinate

    init(id: UUID = UUID(), name: String, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}
