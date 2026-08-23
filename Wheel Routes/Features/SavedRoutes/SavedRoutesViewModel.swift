import Foundation
import Observation

@Observable
@MainActor
final class SavedRoutesViewModel {
    var routes: [SavedRoute] = []
    var errorMessage: String?
    var isLoading = false
    var loadedJourney: Journey?

    private let store: RouteStore
    private let apiClient: any APIClientProtocol

    init(store: RouteStore = RouteStore(), apiClient: any APIClientProtocol) {
        self.store = store
        self.apiClient = apiClient
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

    func reload(route: SavedRoute) async {
        isLoading = true
        errorMessage = nil
        do {
            loadedJourney = try await apiClient.reloadJourney(itineraryID: route.journeyID, plan: route.plan)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
