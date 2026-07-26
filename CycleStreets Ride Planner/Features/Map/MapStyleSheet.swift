import SwiftUI

struct MapStyleSheet: View {
    @Binding var selection: MapStyleOption
    @Environment(\.dismiss) private var dismiss

    private var appleOptions: [MapStyleOption] {
        MapStyleOption.allCases.filter { $0.group == .apple }
    }

    private var osmOptions: [MapStyleOption] {
        MapStyleOption.allCases.filter { $0.group == .openStreetMap }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Apple") {
                    ForEach(appleOptions) { option in
                        row(for: option)
                    }
                }
                Section("OpenStreetMap") {
                    ForEach(osmOptions) { option in
                        row(for: option)
                    }
                }
            }
            .navigationTitle("Map Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(for option: MapStyleOption) -> some View {
        Button {
            selection = option
            dismiss()
        } label: {
            HStack {
                MapStyleThumbnail(option: option)
                Text(option.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if option == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
