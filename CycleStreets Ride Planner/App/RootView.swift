import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Text("Map")
                .tabItem { Label("Map", systemImage: "map") }
            Text("Saved")
                .tabItem { Label("Saved", systemImage: "bookmark") }
            Text("Account")
                .tabItem { Label("Account", systemImage: "person") }
        }
    }
}
