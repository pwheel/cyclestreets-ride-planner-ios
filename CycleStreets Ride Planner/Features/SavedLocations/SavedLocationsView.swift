import SwiftUI
import MapKit

struct SavedLocationsView: View {
    @State private var vm = SavedLocationsViewModel()

    var body: some View {
        List {
            ForEach(vm.locations) { location in
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
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Saved Locations")
        .toolbar { EditButton() }
        .onAppear { vm.load() }
    }
}
