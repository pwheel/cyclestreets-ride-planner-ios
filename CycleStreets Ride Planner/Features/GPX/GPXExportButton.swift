import SwiftUI

struct GPXExportButton: View {
    let journeyID: Int
    @Environment(\.apiClient) private var apiClient
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            if isExporting {
                ProgressView().scaleEffect(0.7)
            } else {
                Label("Export GPX", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
        .sheet(item: $exportedFileURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Export Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export() async {
        isExporting = true
        do {
            let data = try await apiClient.downloadGPX(journeyID: journeyID)
            let filename = "route_\(journeyID).gpx"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            exportedFileURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }
}

// UIActivityViewController wrapper
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
