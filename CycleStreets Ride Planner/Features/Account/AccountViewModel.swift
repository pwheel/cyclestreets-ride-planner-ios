//
//  AccountViewModel.swift
//  CycleStreets Ride Planner
//

import Foundation
import Observation

@Observable
@MainActor
final class AccountViewModel {
    var isLoggedIn = false
    var username: String?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: any APIClientProtocol
    private let keychain: any KeychainHelperProtocol

    init(apiClient: any APIClientProtocol, keychain: any KeychainHelperProtocol = KeychainHelper()) {
        self.apiClient = apiClient
        self.keychain = keychain
        if let session = keychain.load() {
            self.isLoggedIn = true
            self.username = session.username
        }
    }

    func login(username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let token = try await apiClient.login(username: username, password: password)
            try keychain.save(token: token, username: username)
            self.username = username
            self.isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() {
        keychain.delete()
        isLoggedIn = false
        username = nil
    }
}
