//
//  RouteStore.swift
//  CycleStreets Ride Planner
//

import Foundation

final class RouteStore {
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("saved_routes.json")
    }

    func loadAll() throws -> [SavedRoute] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedRoute].self, from: data)
    }

    func save(_ route: SavedRoute) throws {
        var routes = (try? loadAll()) ?? []
        routes.removeAll { $0.id == route.id }
        routes.append(route)
        try JSONEncoder().encode(routes).write(to: fileURL, options: .atomic)
    }

    func delete(id: UUID) throws {
        var routes = try loadAll()
        routes.removeAll { $0.id == id }
        try JSONEncoder().encode(routes).write(to: fileURL, options: .atomic)
    }
}
