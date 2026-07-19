//
//  MapViewModel.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation
import Observation

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

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func search(query: String) async {
        guard !query.isEmpty else { searchResults = []; return }
        do {
            searchResults = try await apiClient.geocode(query: query)
        } catch {
            errorMessage = error.localizedDescription
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
}
