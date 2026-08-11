//
//  LocationStoreTests.swift
//  Wheel RoutesTests
//

import Testing
import Foundation
@testable import Wheel_Routes

final class LocationStoreTests {
    let store: LocationStore

    init() {
        store = LocationStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    @Test func testSaveAndLoadLocation() throws {
        let loc = SavedLocation(name: "Home", coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
        try store.save(loc)
        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Home")
    }
}
