import SwiftUI

struct SavedRoutesView: View {
    @State private var vm: SavedRoutesViewModel
    @AppStorage("useMetric") private var useMetric = true
    let onJourneyLoaded: (Journey) -> Void

    init(apiClient: any APIClientProtocol, onJourneyLoaded: @escaping (Journey) -> Void) {
        _vm = State(initialValue: SavedRoutesViewModel(apiClient: apiClient))
        self.onJourneyLoaded = onJourneyLoaded
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
        .onChange(of: vm.loadedJourney) { _, newValue in
            guard let journey = newValue else { return }
            onJourneyLoaded(journey)
            vm.loadedJourney = nil
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
