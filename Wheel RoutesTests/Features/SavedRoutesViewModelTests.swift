//
//  SavedRoutesViewModelTests.swift
//  Wheel RoutesTests
//

import Testing
import Foundation
@testable import Wheel_Routes

@MainActor
final class SavedRoutesViewModelTests {
    let client: MockAPIClient
    let store: RouteStore
    let vm: SavedRoutesViewModel

    init() {
        client = MockAPIClient()
        store = RouteStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        vm = SavedRoutesViewModel(store: store, apiClient: client)
    }

    private func makeSavedRoute() -> SavedRoute {
        SavedRoute(journeyID: 123700734, name: "My Commute", plan: .quietest,
                   distanceMetres: 6372, timeSeconds: 1914, savedAt: Date())
    }

    @Test func testReloadPopulatesLoadedJourney() async throws {
        let route = makeSavedRoute()
        client.journeyToReturn = client.makeJourney(id: route.journeyID, plan: route.plan)
        await vm.reload(route: route)
        #expect(vm.loadedJourney != nil)
        #expect(vm.loadedJourney?.number == route.journeyID)
    }

    @Test func testReloadSetsErrorMessageOnFailure() async {
        let route = makeSavedRoute()
        client.shouldThrow = URLError(.notConnectedToInternet)
        await vm.reload(route: route)
        #expect(vm.loadedJourney == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test func testReloadSetsIsLoadingDuringFetch() async {
        let route = makeSavedRoute()
        client.journeyToReturn = client.makeJourney(id: route.journeyID, plan: route.plan)
        #expect(vm.isLoading == false)
        await vm.reload(route: route)
        #expect(vm.isLoading == false)
    }
}
