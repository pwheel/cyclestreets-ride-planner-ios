import SwiftUI

struct RootView: View {
    @Environment(\.apiClient) private var apiClient

    var body: some View {
        TabView {
            NavigationStack {
                MapView(apiClient: apiClient)
            }
            .tabItem { Label("Map", systemImage: "map") }

            Text("Saved")
                .tabItem { Label("Saved", systemImage: "bookmark") }

            Text("Account")
                .tabItem { Label("Account", systemImage: "person") }
        }
    }
}
