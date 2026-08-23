//
//  PhotonLocationSearchProvider.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

/// Real `LocationSearchProviding` implementation backed by Photon's public
/// demo API (https://photon.komoot.io). The actual network hop here isn't
/// unit-tested directly — same accepted gap as `APIClient`'s own
/// `session.data(from:)` calls; `PhotonEndpoint`/`PhotonGeocoderDecoder`
/// carry the real test coverage.
final class PhotonLocationSearchProvider: LocationSearchProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place] {
        let url = try PhotonEndpoint.search(query: query, near: coordinate)
        let (data, response) = try await session.data(from: url)
        // Photon's public demo policy is "reasonable use only — extensive
        // usage will be throttled or completely banned," so a non-2xx
        // response is an expected failure mode, not a rare edge case.
        // Without this check, a throttled/error body falls straight into
        // JSONDecoder and surfaces as a confusing generic decode error.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try PhotonGeocoderDecoder.decode(data)
    }
}
