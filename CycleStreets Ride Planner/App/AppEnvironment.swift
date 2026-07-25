import SwiftUI

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: any APIClientProtocol = {
        let key = (try? APIKey.load()) ?? ""
        return APIClient(apiKey: key)
    }()
}

extension EnvironmentValues {
    var apiClient: any APIClientProtocol {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
