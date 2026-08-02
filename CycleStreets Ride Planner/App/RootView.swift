import SwiftUI

struct RootView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.locationService) private var locationService
    @State private var selectedTab: Tab = .map
    @State private var pendingMapJourney: Journey?
    @State private var pendingPlaceSelection: PendingPlaceSelection?

    enum Tab { case map, saved, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(apiClient: apiClient, locationService: locationService, pendingJourney: $pendingMapJourney, pendingPlaceSelection: $pendingPlaceSelection)
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
                    NavigationLink("Saved Locations") {
                        SavedLocationsView { place, role in
                            pendingPlaceSelection = PendingPlaceSelection(place: place, role: role)
                            selectedTab = .map
                        }
                    }
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
