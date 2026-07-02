import Foundation
import Observation

@Observable
@MainActor
final class SavedRoutesViewModel {
    var routes: [SavedRoute] = []
    var errorMessage: String?

    private let store: RouteStore

    init(store: RouteStore = RouteStore()) {
        self.store = store
    }

    func load() {
        routes = (try? store.loadAll()) ?? []
    }

    func save(journey: Journey, name: String? = nil) {
        let route = journey.asSavedRoute(name: name)
        try? store.save(route)
        load()
    }

    func delete(at offsets: IndexSet) {
        offsets.map { routes[$0].id }.forEach { try? store.delete(id: $0) }
        load()
    }
}
