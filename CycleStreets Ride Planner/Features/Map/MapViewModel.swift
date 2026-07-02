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
}
