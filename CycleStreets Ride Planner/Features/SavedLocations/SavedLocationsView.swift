import SwiftUI
import MapKit

struct SavedLocationsView: View {
    @State private var vm = SavedLocationsViewModel()
    @State private var locationForRoleChoice: SavedLocation?
    let onPlaceSelected: (Place, WaypointRole) -> Void

    var body: some View {
        List {
            ForEach(vm.locations) { location in
                Button {
                    locationForRoleChoice = location
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text(location.name).font(.body)
                            Text(String(format: "%.4f, %.4f",
                                        location.coordinate.latitude,
                                        location.coordinate.longitude))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Saved Locations")
        .toolbar { EditButton() }
        .onAppear { vm.load() }
        .confirmationDialog(
            "Use \(locationForRoleChoice?.name ?? "") as…",
            isPresented: Binding(
                get: { locationForRoleChoice != nil },
                set: { if !$0 { locationForRoleChoice = nil } }
            ),
            presenting: locationForRoleChoice
        ) { location in
            Button("Start (From)") { onPlaceSelected(place(for: location), .from) }
            Button("Destination (To)") { onPlaceSelected(place(for: location), .to) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func place(for location: SavedLocation) -> Place {
        Place(id: location.id.uuidString, name: location.name, near: nil, coordinate: location.coordinate)
    }
}
