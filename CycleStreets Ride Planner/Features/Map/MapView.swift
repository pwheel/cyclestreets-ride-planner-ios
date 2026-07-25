import SwiftUI
import MapKit

struct MapView: View {
    @State private var vm: MapViewModel
    @Environment(\.apiClient) private var apiClient
    @Binding var pendingJourney: Journey?
    @Binding var pendingPlaceSelection: PendingPlaceSelection?
    @State private var searchText = ""
    @State private var selectingFor: WaypointRole = .from
    @FocusState private var isSearchFieldFocused: Bool
    @State private var savedLocationsVM = SavedLocationsViewModel()
    @State private var isPresentingLocationSavedConfirmation = false
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    init(apiClient: any APIClientProtocol, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
        let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
        let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
        _vm = State(initialValue: MapViewModel(apiClient: apiClient, initialSelectedPlan: initialPlan))
        _pendingJourney = pendingJourney
        _pendingPlaceSelection = pendingPlaceSelection
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 0) {
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Plan Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let journey = vm.currentJourney {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Itinerary") {
                        ItineraryView(journey: journey, apiClient: apiClient)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        vm.clearRoute()
                        selectingFor = .from
                    }
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
        .alert("Location Saved", isPresented: $isPresentingLocationSavedConfirmation) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: pendingJourney) { _, newValue in
            guard let journey = newValue else { return }
            vm.loadJourney(journey)
            if let end = journey.allCoordinates.last {
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: end,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
            pendingJourney = nil
        }
        .onChange(of: pendingPlaceSelection) { _, newValue in
            guard let selection = newValue else { return }
            if selection.role == .from { selectingFor = .to }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            Task {
                await vm.selectPlace(selection.place, as: selection.role)
                pendingPlaceSelection = nil
            }
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(nonSelectedRouteOptions) { option in
                if let journey = option.journey {
                    MapPolyline(coordinates: journey.allCoordinates)
                        .stroke(color(for: option.plan), lineWidth: 3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                MapPolyline(coordinates: journey.allCoordinates)
                    .stroke(color(for: selectedOption.plan), lineWidth: 5)
            }
            if let from = vm.fromPlace {
                Marker("Start", coordinate: from.clCoordinate).tint(.green)
            }
            if let to = vm.toPlace {
                Marker("End", coordinate: to.clCoordinate).tint(.red)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
    }

    private var nonSelectedRouteOptions: [RouteOption] {
        vm.routeOptions.filter { $0.plan != vm.selectedPlan }
    }

    private func color(for plan: RoutePlan) -> Color {
        switch plan {
        case .quietest: return .green
        case .balanced: return .yellow
        case .fastest: return .red
        }
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            ForEach(vm.routeOptions) { option in
                Button {
                    vm.selectedPlan = option.plan
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: option.plan))
                            .frame(width: 10, height: 10)
                        Text(option.plan.displayName)
                        if option.errorMessage != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        option.plan == vm.selectedPlan ? Color.secondary.opacity(0.2) : Color.clear,
                        in: Capsule()
                    )
                }
                .disabled(option.journey == nil)
                .opacity(option.journey == nil ? 0.5 : 1)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                selectingFor == .from ? "Search start location" : "Search end location",
                text: $searchText
            )
            .submitLabel(.search)
            .focused($isSearchFieldFocused)
            .onSubmit { Task { await vm.search(query: searchText) } }
            .onChange(of: searchText) { _, newValue in vm.searchTextChanged(newValue) }
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
            HStack {
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
                Spacer()
                Button {
                    savedLocationsVM.save(name: place.name, coordinate: place.coordinate)
                    isPresentingLocationSavedConfirmation = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.borderless)
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
        let role = selectingFor
        if role == .from { selectingFor = .to }
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
        Task { await vm.selectPlace(place, as: role) }
    }
}
