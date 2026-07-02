//
//  MockKeychainHelper.swift
//  CycleStreets Ride PlannerTests
//

import Foundation
@testable import CycleStreets_Ride_Planner

final class MockKeychainHelper: KeychainHelperProtocol {
    private var stored: UserSession?
    func save(token: String, username: String) { stored = UserSession(username: username, token: token) }
    func load() -> UserSession? { stored }
    func delete() { stored = nil }
}
