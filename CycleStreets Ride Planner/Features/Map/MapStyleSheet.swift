import SwiftUI

struct MapStyleSheet: View {
    @Binding var selection: MapStyleOption
    let thunderforestAPIKey: String
    @Environment(\.dismiss) private var dismiss

    private static let placeholderThunderforestKey = "YOUR_THUNDERFOREST_API_KEY_HERE"

    /// `true` when a style needing a Thunderforest key can't actually load tiles right now —
    /// the key failed to load (empty) or is still the tracked placeholder value.
    private func isDegraded(_ option: MapStyleOption) -> Bool {
        option.requiresThunderforestKey
            && (thunderforestAPIKey.isEmpty || thunderforestAPIKey == Self.placeholderThunderforestKey)
    }

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
        let degraded = isDegraded(option)
        return Button {
            selection = option
            dismiss()
        } label: {
            HStack {
                MapStyleThumbnail(option: option)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(option.displayName)
                            .foregroundStyle(.primary)
                        if degraded {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if degraded {
                        Text("Requires a Thunderforest API key — see docs/SPEC.md")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if option == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .opacity(degraded ? 0.6 : 1)
        }
    }
}
