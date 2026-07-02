import SwiftUI
import MapKit

struct MapView: View {
    @State private var vm: MapViewModel
    @Environment(\.apiClient) private var apiClient
    @State private var searchText = ""
    @State private var selectingFor: WaypointRole = .from
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    enum WaypointRole { case from, to }

    init(apiClient: any APIClientProtocol) {
        _vm = State(initialValue: MapViewModel(apiClient: apiClient))
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 0) {
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Plan Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.currentJourney != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") { vm.clearRoute() }
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView().scaleEffect(1.5) }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var map: some View {
        Map(position: $position) {
            if let journey = vm.currentJourney {
                MapPolyline(coordinates: journey.allCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            if let from = vm.fromPlace {
                Marker("Start", coordinate: from.clCoordinate).tint(.green)
            }
            if let to = vm.toPlace {
                Marker("End", coordinate: to.clCoordinate).tint(.red)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                selectingFor == .from ? "Search start location" : "Search end location",
                text: $searchText
            )
            .submitLabel(.search)
            .onSubmit { Task { await vm.search(query: searchText) } }
            if !searchText.isEmpty {
                Button { searchText = ""; vm.searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $selectingFor) {
                Text("From").tag(WaypointRole.from)
                Text("To").tag(WaypointRole.to)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var resultsList: some View {
        List(vm.searchResults) { place in
            Button {
                selectPlace(place)
            } label: {
                VStack(alignment: .leading) {
                    Text(place.name).font(.body)
                    if let near = place.near {
                        Text(near).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func selectPlace(_ place: Place) {
        searchText = ""
        vm.searchResults = []
        if selectingFor == .from {
            vm.fromPlace = place
            selectingFor = .to
        } else {
            vm.toPlace = place
        }
        if let from = vm.fromPlace, let to = vm.toPlace {
            Task { await vm.planRoute(from: from.clCoordinate, to: to.clCoordinate) }
        }
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }
}
