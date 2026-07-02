import SwiftUI

struct SavedRoutesView: View {
    @State private var vm = SavedRoutesViewModel()
    @AppStorage("useMetric") private var useMetric = true

    var body: some View {
        List {
            ForEach(vm.routes) { route in
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
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Saved Routes")
        .toolbar { EditButton() }
        .onAppear { vm.load() }
    }
}
