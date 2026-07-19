//
//  ItineraryView.swift
//  CycleStreets Ride Planner
//

import SwiftUI

struct ItineraryView: View {
    let journey: Journey
    let apiClient: any APIClientProtocol
    @AppStorage("useMetric") private var useMetric = true
    @State private var savedRoutesVM: SavedRoutesViewModel
    @State private var isPresentingSaveAlert = false
    @State private var isPresentingSavedConfirmation = false
    @State private var routeName = ""

    init(journey: Journey, apiClient: any APIClientProtocol) {
        self.journey = journey
        self.apiClient = apiClient
        _savedRoutesVM = State(initialValue: SavedRoutesViewModel(apiClient: apiClient))
    }

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    routeName = ""
                    isPresentingSaveAlert = true
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                GPXExportButton(journeyID: journey.number, plan: journey.plan)
            }
        }
        .alert("Save Route", isPresented: $isPresentingSaveAlert) {
            TextField("Route name", text: $routeName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
                savedRoutesVM.save(journey: journey, name: trimmed.isEmpty ? nil : trimmed)
                isPresentingSavedConfirmation = true
            }
        } message: {
            Text("Enter a name, or leave blank to use a default name.")
        }
        .alert("Route Saved", isPresented: $isPresentingSavedConfirmation) {
            Button("OK", role: .cancel) {}
        }
    }
}
