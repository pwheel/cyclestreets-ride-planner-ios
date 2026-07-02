//
//  AccountView.swift
//  CycleStreets Ride Planner
//

import SwiftUI

struct AccountView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var vm: AccountViewModel
    @State private var username = ""
    @State private var password = ""

    init(apiClient: any APIClientProtocol) {
        _vm = State(initialValue: AccountViewModel(apiClient: apiClient))
    }

    var body: some View {
        if vm.isLoggedIn {
            loggedInView
        } else {
            loginForm
        }
    }

    private var loggedInView: some View {
        List {
            Section {
                Label(vm.username ?? "", systemImage: "person.circle")
                    .font(.headline)
            }
            Section {
                Button("Sign Out", role: .destructive) { vm.logout() }
            }
        }
        .navigationTitle("Account")
    }

    private var loginForm: some View {
        Form {
            Section("Sign in to CycleStreets") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            Section {
                Button {
                    Task { await vm.login(username: username, password: password) }
                } label: {
                    if vm.isLoading { ProgressView() }
                    else { Text("Sign In").frame(maxWidth: .infinity) }
                }
                .disabled(username.isEmpty || password.isEmpty || vm.isLoading)
            }
        }
        .navigationTitle("Account")
        .alert("Sign In Failed", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
