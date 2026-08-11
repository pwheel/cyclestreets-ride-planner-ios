import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultRoutePlan") private var defaultRoutePlan = RoutePlan.balanced.rawValue
    @AppStorage("useMetric") private var useMetric = true

    var body: some View {
        Form {
            Section("Routing") {
                Picker("Default route type", selection: $defaultRoutePlan) {
                    ForEach(RoutePlan.allCases, id: \.rawValue) { plan in
                        Text(plan.displayName).tag(plan.rawValue)
                    }
                }
            }
            Section("Units") {
                Toggle("Use metric (km)", isOn: $useMetric)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersionString)
                Link("CycleStreets website", destination: URL(string: "https://www.cyclestreets.net")!)
                Link("GNU GPL License", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
        }
        .navigationTitle("Settings")
    }
}

private extension Bundle {
    var appVersionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
