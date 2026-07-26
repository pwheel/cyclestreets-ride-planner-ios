import SwiftUI
import MapKit
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI

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
    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @State private var position = MapCameraPosition.region(MapView.initialRegion)
    @State private var mapLibreCamera = MapView.mapViewCamera(for: MapView.initialRegion)
    @State private var isPresentingMapStyleSheet = false
    @AppStorage("mapStyle") private var mapStyleRawValue = MapStyleOption.defaultOption.rawValue
    @Environment(\.thunderforestAPIKey) private var thunderforestAPIKey

    init(apiClient: any APIClientProtocol, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
        let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
        let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
        _vm = State(initialValue: MapViewModel(apiClient: apiClient, initialSelectedPlan: initialPlan))
        _pendingJourney = pendingJourney
        _pendingPlaceSelection = pendingPlaceSelection
    }

    private static func mapViewCamera(for region: MKCoordinateRegion) -> MapViewCamera {
        let center = region.center
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let sw = CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude - halfLon)
        let ne = CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude + halfLon)
        return .boundingBox(MLNCoordinateBounds(sw: sw, ne: ne))
    }

    private func updateCamera(to region: MKCoordinateRegion) {
        position = .region(region)
        mapLibreCamera = MapView.mapViewCamera(for: region)
    }

    private var selectedMapStyle: MapStyleOption {
        get { MapStyleOption(rawValue: mapStyleRawValue) ?? .defaultOption }
        nonmutating set { mapStyleRawValue = newValue.rawValue }
    }

    private var mapStyleBinding: Binding<MapStyleOption> {
        Binding(get: { selectedMapStyle }, set: { selectedMapStyle = $0 })
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
        .overlay(alignment: .bottomTrailing) { layersButton }
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
                    updateCamera(to: MKCoordinateRegion(
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
                updateCamera(to: MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            Task {
                await vm.selectPlace(selection.place, as: selection.role)
                if vm.fromPlace != nil && vm.toPlace != nil {
                    isSearchFieldFocused = false
                }
                pendingPlaceSelection = nil
            }
        }
    }

    @ViewBuilder
    private var map: some View {
        if let appleStyle = selectedMapStyle.appleMapStyle {
            appleMap(style: appleStyle)
        } else if let document = selectedMapStyle.mapLibreStyleDocument(thunderforestKey: thunderforestAPIKey) {
            osmMap(document: document)
        }
    }

    private func appleMap(style: MapStyle) -> some View {
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
        .mapStyle(style)
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
    }

    private func osmMap(document: MapLibreStyleDocument) -> some View {
        MapLibreSwiftUI.MapView(styleURL: osmStyleURL(for: document), camera: $mapLibreCamera) {
            for option in nonSelectedRouteOptions {
                if let journey = option.journey {
                    let source = ShapeSource(identifier: "route-\(option.plan.rawValue)") {
                        MLNPolylineFeature(coordinates: journey.allCoordinates)
                    }
                    LineStyleLayer(identifier: "route-\(option.plan.rawValue)-line", source: source)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .lineColor(uiColor(for: option.plan))
                        .lineWidth(3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                let source = ShapeSource(identifier: "route-\(selectedOption.plan.rawValue)-selected") {
                    MLNPolylineFeature(coordinates: journey.allCoordinates)
                }
                LineStyleLayer(identifier: "route-\(selectedOption.plan.rawValue)-selected-line", source: source)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(uiColor(for: selectedOption.plan))
                    .lineWidth(5)
            }
            if let from = vm.fromPlace {
                let startSource = ShapeSource(identifier: "waypoint-start") {
                    MLNPointFeature(coordinate: from.clCoordinate)
                }
                SymbolStyleLayer(identifier: "waypoint-start-symbol", source: startSource)
                    .iconImage(UIImage(systemName: "mappin.circle.fill")!.withRenderingMode(.alwaysTemplate))
                    .iconColor(.systemGreen)
            }
            if let to = vm.toPlace {
                let endSource = ShapeSource(identifier: "waypoint-end") {
                    MLNPointFeature(coordinate: to.clCoordinate)
                }
                SymbolStyleLayer(identifier: "waypoint-end-symbol", source: endSource)
                    .iconImage(UIImage(systemName: "mappin.circle.fill")!.withRenderingMode(.alwaysTemplate))
                    .iconColor(.systemRed)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
    }

    private func osmStyleURL(for document: MapLibreStyleDocument) -> URL {
        (try? document.writeToTemporaryFile(named: selectedMapStyle.rawValue))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("map-style-fallback.json")
    }

    private func uiColor(for plan: RoutePlan) -> UIColor {
        switch plan {
        case .quietest: return .systemGreen
        case .balanced: return .systemYellow
        case .fastest: return .systemRed
        }
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
                        if option.failed {
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
                .disabled(option.failed)
                .opacity(option.failed ? 0.5 : 1)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private var layersButton: some View {
        Button {
            isPresentingMapStyleSheet = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .padding()
        .sheet(isPresented: $isPresentingMapStyleSheet) {
            MapStyleSheet(selection: mapStyleBinding)
        }
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
            updateCamera(to: MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
        Task {
            await vm.selectPlace(place, as: role)
            if vm.fromPlace != nil && vm.toPlace != nil {
                isSearchFieldFocused = false
            }
        }
    }
}
