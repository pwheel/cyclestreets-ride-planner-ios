import SwiftUI

struct RootView: View {
    @Environment(\.apiClient) private var apiClient

    var body: some View {
        TabView {
            NavigationStack {
                MapView(apiClient: apiClient)
            }
            .tabItem { Label("Map", systemImage: "map") }

            NavigationStack {
                List {
                    NavigationLink("Saved Routes") { SavedRoutesView() }
                    NavigationLink("Saved Locations") { SavedLocationsView() }
                }
                .navigationTitle("Saved")
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }

            Text("Account")
                .tabItem { Label("Account", systemImage: "person") }
        }
    }
}
