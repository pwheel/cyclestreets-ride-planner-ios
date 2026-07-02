//
//  ItineraryView.swift
//  CycleStreets Ride Planner
//

import SwiftUI

struct ItineraryView: View {
    let journey: Journey
    @AppStorage("useMetric") private var useMetric = true

    private var vm: ItineraryViewModel {
        ItineraryViewModel(journey: journey, useMetric: useMetric)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label(vm.totalDistance, systemImage: "arrow.left.and.right")
                    Spacer()
                    Label(vm.totalTime, systemImage: "clock")
                }
                .font(.headline)
            } header: {
                Text(journey.plan.displayName + " route")
            }

            Section("Turn-by-turn") {
                ForEach(vm.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.instruction).font(.body)
                        Text(row.streetName).font(.caption).foregroundStyle(.secondary)
                        Text("\(row.distance) · \(row.duration)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Itinerary")
        // TODO: wire up GPXExportButton in Task 9
    }
}
