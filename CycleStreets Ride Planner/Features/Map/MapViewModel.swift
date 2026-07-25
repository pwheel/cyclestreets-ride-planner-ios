//
//  MapViewModel.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation
import Observation

enum WaypointRole: Equatable { case from, to }

/// A place selected outside `MapView`'s own search flow (e.g. from
/// Saved Locations), paired with which waypoint it should fill.
struct PendingPlaceSelection: Equatable {
    let place: Place
    let role: WaypointRole
}

@Observable
@MainActor
final class MapViewModel {
    var searchResults: [Place] = []
    var fromPlace: Place?
    var toPlace: Place?
    var currentJourney: Journey?
    var isLoading = false
    var errorMessage: String?
    var routePlan: RoutePlan = .balanced
    var searchDebounceMilliseconds: UInt64 = 300

    private let apiClient: any APIClientProtocol
    private var searchDebounceTask: Task<Void, Never>?

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func search(query: String) async {
        searchDebounceTask?.cancel()
        guard !query.isEmpty else { searchResults = []; return }
        do {
            searchResults = try await apiClient.geocode(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called as the user types in the search field to provide typeahead
    /// suggestions, debouncing so each keystroke doesn't fire its own
    /// network request.
    func searchTextChanged(_ text: String) {
        searchDebounceTask?.cancel()
        guard !text.isEmpty else { searchResults = []; return }
        let milliseconds = searchDebounceMilliseconds
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            await search(query: text)
        }
    }

    func planRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        isLoading = true
        errorMessage = nil
        do {
            currentJourney = try await apiClient.planJourney(from: from, to: to, plan: routePlan)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func clearRoute() {
        currentJourney = nil
        fromPlace = nil
        toPlace = nil
        searchResults = []
        errorMessage = nil
    }

    /// Populates the map from a journey obtained outside the normal
    /// search flow (e.g. a reloaded saved route), deriving placeholder
    /// from/to markers from the journey's own coordinates since no
    /// searched `Place` exists for it.
    func loadJourney(_ journey: Journey) {
        currentJourney = journey
        searchResults = []
        errorMessage = nil
        let coordinates = journey.allCoordinates
        if let start = coordinates.first {
            fromPlace = Place(id: UUID().uuidString, name: "Start", near: nil,
                               coordinate: Coordinate(longitude: start.longitude, latitude: start.latitude))
        }
        if let end = coordinates.last {
            toPlace = Place(id: UUID().uuidString, name: "End", near: nil,
                             coordinate: Coordinate(longitude: end.longitude, latitude: end.latitude))
        }
    }

    /// Assigns a place to the given waypoint and, once both from and to
    /// are set, plans the route — matching the behavior of picking a
    /// place from search results.
    func selectPlace(_ place: Place, as role: WaypointRole) async {
        switch role {
        case .from: fromPlace = place
        case .to: toPlace = place
        }
        if let from = fromPlace, let to = toPlace {
            await planRoute(from: from.clCoordinate, to: to.clCoordinate)
        }
    }
}
