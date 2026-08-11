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
        let (data, _) = try await session.data(from: url)
        return try PhotonGeocoderDecoder.decode(data)
    }
}
