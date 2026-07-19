import SwiftUI

struct SavedRoutesView: View {
    let apiClient: any APIClientProtocol
    @State private var vm: SavedRoutesViewModel
    @AppStorage("useMetric") private var useMetric = true

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
        _vm = State(initialValue: SavedRoutesViewModel(apiClient: apiClient))
    }

    var body: some View {
        List {
            ForEach(vm.routes) { route in
                Button {
                    Task { await vm.reload(route: route) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name).font(.headline)
                        HStack {
                            Text(route.plan.displayName)
                            Spacer()
                            let j = Journey(number: route.journeyID, plan: route.plan,
                                            lengthMetres: route.distanceMetres,
                                            timeSeconds: route.timeSeconds, segments: [])
                            Text(j.formattedDistance(metric: useMetric))
                            Text("·")
                            Text(j.formattedDuration())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(.primary)
            }
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Saved Routes")
        .toolbar { EditButton() }
        .onAppear { vm.load() }
        .overlay {
            if vm.isLoading { ProgressView().scaleEffect(1.5) }
        }
        .navigationDestination(isPresented: Binding(
            get: { vm.loadedJourney != nil },
            set: { if !$0 { vm.loadedJourney = nil } }
        )) {
            if let journey = vm.loadedJourney {
                ItineraryView(journey: journey, apiClient: apiClient)
            }
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
}
