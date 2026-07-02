//
//  RouteStoreTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
@testable import CycleStreets_Ride_Planner

final class RouteStoreTests {
    let store: RouteStore

    init() {
        store = RouteStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    @Test func testSaveAndLoadRoute() throws {
        let route = SavedRoute(journeyID: 42, name: "My Commute", plan: .balanced,
                               distanceMetres: 3200, timeSeconds: 900,
                               savedAt: Date())
        try store.save(route)
        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].journeyID == 42)
        #expect(loaded[0].name == "My Commute")
    }

    @Test func testDeleteRoute() throws {
        let route = SavedRoute(journeyID: 99, name: "Park Ride", plan: .quietest,
                               distanceMetres: 1500, timeSeconds: 400,
                               savedAt: Date())
        try store.save(route)
        try store.delete(id: route.id)
        let loaded = try store.loadAll()
        #expect(loaded.isEmpty)
    }
}
