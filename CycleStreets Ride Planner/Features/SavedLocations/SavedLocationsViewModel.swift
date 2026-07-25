import Foundation
import Observation

@Observable
@MainActor
final class SavedLocationsViewModel {
    var locations: [SavedLocation] = []

    private let store: LocationStore

    init(store: LocationStore = LocationStore()) {
        self.store = store
    }

    func load() {
        locations = (try? store.loadAll()) ?? []
    }

    func save(name: String, coordinate: Coordinate) {
        let loc = SavedLocation(name: name, coordinate: coordinate)
        try? store.save(loc)
        load()
    }

    func delete(at offsets: IndexSet) {
        offsets.map { locations[$0].id }.forEach { try? store.delete(id: $0) }
        load()
    }
}
