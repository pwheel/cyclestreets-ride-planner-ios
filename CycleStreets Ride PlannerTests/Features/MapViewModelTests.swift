//
//  MapViewModelTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
import CoreLocation
@testable import CycleStreets_Ride_Planner

@MainActor
final class MapViewModelTests {
    let client: MockAPIClient
    let vm: MapViewModel

    init() {
        client = MockAPIClient()
        vm = MapViewModel(apiClient: client)
    }

    @Test func testSearchUpdatesPlaces() async throws {
        client.placesToReturn = [
            Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
                  coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
        ]
        await vm.search(query: "Cambridge")
        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults[0].name == "Cambridge")
    }

    @Test func testPlanRoutePopulatesJourney() async throws {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.currentJourney != nil)
        #expect(vm.currentJourney?.number == journey.number)
    }

    @Test func testPlanRouteErrorSetsErrorMessage() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.errorMessage != nil)
    }

    @Test func testClearRouteResetsState() async {
        client.journeyToReturn = client.makeJourney()
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        vm.clearRoute()
        #expect(vm.currentJourney == nil)
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
    }

    @Test func testLoadJourneySetsCurrentJourney() {
        let journey = client.makeJourney()
        vm.loadJourney(journey)
        #expect(vm.currentJourney == journey)
    }

    @Test func testLoadJourneyDerivesFromAndToPlacesFromCoordinates() {
        let journey = client.makeJourney()
        let first = journey.allCoordinates.first!
        let last = journey.allCoordinates.last!
        vm.loadJourney(journey)
        #expect(vm.fromPlace?.coordinate.longitude == first.longitude)
        #expect(vm.fromPlace?.coordinate.latitude == first.latitude)
        #expect(vm.toPlace?.coordinate.longitude == last.longitude)
        #expect(vm.toPlace?.coordinate.latitude == last.latitude)
    }

    @Test func testLoadJourneyClearsSearchResultsAndError() {
        client.placesToReturn = [
            Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
        ]
        vm.searchResults = client.placesToReturn
        vm.errorMessage = "stale error"
        vm.loadJourney(client.makeJourney())
        #expect(vm.searchResults.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func testSelectPlaceAsFromOnlySetsFromPlace() async {
        let place = Place(id: "1", name: "Home", near: nil, coordinate: Coordinate(longitude: 0.1, latitude: 52.0))
        await vm.selectPlace(place, as: .from)
        #expect(vm.fromPlace == place)
        #expect(vm.toPlace == nil)
        #expect(vm.currentJourney == nil)
    }

    @Test func testSelectPlaceAsToAfterFromTriggersPlanRoute() async {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = Place(id: "1", name: "Home", near: nil, coordinate: Coordinate(longitude: 0.1, latitude: 52.0))
        let to = Place(id: "2", name: "Work", near: nil, coordinate: Coordinate(longitude: 0.2, latitude: 52.1))
        await vm.selectPlace(from, as: .from)
        await vm.selectPlace(to, as: .to)
        #expect(vm.toPlace == to)
        #expect(vm.currentJourney?.number == journey.number)
    }
}
