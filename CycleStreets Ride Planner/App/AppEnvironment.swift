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

private struct ThunderforestAPIKeyKey: EnvironmentKey {
    static let defaultValue: String = (try? APIKey.loadThunderforestKey()) ?? ""
}

extension EnvironmentValues {
    var thunderforestAPIKey: String {
        get { self[ThunderforestAPIKeyKey.self] }
        set { self[ThunderforestAPIKeyKey.self] = newValue }
    }
}

private struct LocationServiceKey: EnvironmentKey {
    static let defaultValue: any LocationServiceProtocol = LocationService()
}

extension EnvironmentValues {
    var locationService: any LocationServiceProtocol {
        get { self[LocationServiceKey.self] }
        set { self[LocationServiceKey.self] = newValue }
    }
}

private struct LocationSearchProviderKey: EnvironmentKey {
    static let defaultValue: any LocationSearchProviding = PhotonLocationSearchProvider()
}

extension EnvironmentValues {
    var locationSearchProvider: any LocationSearchProviding {
        get { self[LocationSearchProviderKey.self] }
        set { self[LocationSearchProviderKey.self] = newValue }
    }
}
