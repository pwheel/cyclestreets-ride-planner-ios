import SwiftUI

struct RootView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var selectedTab: Tab = .map
    @State private var pendingMapJourney: Journey?

    enum Tab { case map, saved, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(apiClient: apiClient, pendingJourney: $pendingMapJourney)
            }
            .tabItem { Label("Map", systemImage: "map") }
            .tag(Tab.map)

            NavigationStack {
                List {
                    NavigationLink("Saved Routes") {
                        SavedRoutesView(apiClient: apiClient) { journey in
                            pendingMapJourney = journey
                            selectedTab = .map
                        }
                    }
                    NavigationLink("Saved Locations") { SavedLocationsView() }
                }
                .navigationTitle("Saved")
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }
            .tag(Tab.saved)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(Tab.settings)
        }
    }
}
