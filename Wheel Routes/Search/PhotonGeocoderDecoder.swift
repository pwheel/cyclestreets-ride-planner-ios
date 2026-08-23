//
//  PhotonGeocoderDecoder.swift
//  CycleStreets Ride Planner
//

import Foundation

/// Decodes Photon's GeoJSON `FeatureCollection` response
/// (https://photon.komoot.io) into `Place` values. Unlike CycleStreets'
/// geocoder, the API returns no stable per-result identifier, so each
/// `Place.id` is synthesized — same as `GeocoderDecoder` did.
enum PhotonGeocoderDecoder {

    private struct RawResponse: Decodable {
        let features: [RawFeature]
    }

    private struct RawFeature: Decodable {
        let properties: RawProperties
        let geometry: RawGeometry
    }

    private struct RawProperties: Decodable {
        let name: String?
        let street: String?
        let city: String?
        let district: String?
        let county: String?
        let state: String?
        let country: String?
    }

    private struct RawGeometry: Decodable {
        let coordinates: [Double]
    }

    static func decode(_ data: Data) throws -> [Place] {
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        return raw.features.compactMap { feature -> Place? in
            guard feature.geometry.coordinates.count == 2 else { return nil }
            let coordinate = Coordinate(
                longitude: feature.geometry.coordinates[0],
                latitude: feature.geometry.coordinates[1]
            )
            let props = feature.properties
            let name = props.name ?? props.street ?? "Unknown location"
            let nearParts = [props.city ?? props.district, props.county, props.state, props.country]
                .compactMap { $0 }
            let near = nearParts.isEmpty ? nil : nearParts.joined(separator: ", ")
            return Place(id: UUID().uuidString, name: name, near: near, coordinate: coordinate)
        }
    }
}
