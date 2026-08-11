//
//  GeocoderDecoder.swift
//  Wheel Routes
//

import Foundation

/// Decodes the CycleStreets v2 geocoder's GeoJSON `FeatureCollection` response
/// into `Place` values. The API returns no stable per-result identifier, so
/// each `Place.id` is synthesized.
enum GeocoderDecoder {

    private struct RawResponse: Decodable {
        let features: [RawFeature]
    }

    private struct RawFeature: Decodable {
        let properties: RawProperties
        let geometry: RawGeometry
    }

    private struct RawProperties: Decodable {
        let name: String
        let near: String?
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
            return Place(
                id: UUID().uuidString,
                name: feature.properties.name,
                near: feature.properties.near,
                coordinate: coordinate
            )
        }
    }
}
