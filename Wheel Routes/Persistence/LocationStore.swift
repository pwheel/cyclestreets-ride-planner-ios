//
//  LocationStore.swift
//  Wheel Routes
//

import Foundation

final class LocationStore {
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("saved_locations.json")
    }

    func loadAll() throws -> [SavedLocation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedLocation].self, from: data)
    }

    func save(_ location: SavedLocation) throws {
        var locations = (try? loadAll()) ?? []
        locations.removeAll { $0.id == location.id }
        locations.append(location)
        try JSONEncoder().encode(locations).write(to: fileURL, options: .atomic)
    }

    func delete(id: UUID) throws {
        var locations = try loadAll()
        locations.removeAll { $0.id == id }
        try JSONEncoder().encode(locations).write(to: fileURL, options: .atomic)
    }
}
