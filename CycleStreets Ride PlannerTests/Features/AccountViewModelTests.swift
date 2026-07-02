//
//  AccountViewModelTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
@testable import CycleStreets_Ride_Planner

@MainActor
final class AccountViewModelTests {
    let client: MockAPIClient
    let vm: AccountViewModel

    init() {
        client = MockAPIClient()
        vm = AccountViewModel(apiClient: client, keychain: MockKeychainHelper())
    }

    @Test func testLoginSuccessSetsSession() async {
        client.tokenToReturn = "abc123"
        await vm.login(username: "alice", password: "secret")
        #expect(vm.isLoggedIn)
        #expect(vm.username == "alice")
    }

    @Test func testLoginFailureSetsError() async {
        client.shouldThrow = URLError(.userAuthenticationRequired)
        await vm.login(username: "alice", password: "wrong")
        #expect(!vm.isLoggedIn)
        #expect(vm.errorMessage != nil)
    }

    @Test func testLogoutClearsSession() async {
        client.tokenToReturn = "abc123"
        await vm.login(username: "alice", password: "secret")
        vm.logout()
        #expect(!vm.isLoggedIn)
        #expect(vm.username == nil)
    }
}
