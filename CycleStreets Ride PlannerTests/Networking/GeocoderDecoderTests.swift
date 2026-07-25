//
//  GeocoderDecoderTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
@testable import CycleStreets_Ride_Planner

struct GeocoderDecoderTests {

    @Test func decodesFeatureCollectionIntoPlaces() throws {
        let places = try GeocoderDecoder.decode(sampleGeoJSON)
        #expect(places.count == 2)
        #expect(places[0].name == "Downing Street")
        #expect(places[0].near == "City of Westminster, London")
        #expect(places[0].coordinate.longitude == -0.1275)
        #expect(places[0].coordinate.latitude == 51.5034)
    }

    @Test func handlesMissingNearField() throws {
        let places = try GeocoderDecoder.decode(sampleGeoJSONWithoutNear)
        #expect(places.count == 1)
        #expect(places[0].near == nil)
    }

    @Test func placesHaveDistinctIdentifiers() throws {
        let places = try GeocoderDecoder.decode(sampleGeoJSON)
        #expect(places[0].id != places[1].id)
    }
}

private let sampleGeoJSON = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "name": "Downing Street",
                "near": "City of Westminster, London",
                "bbox": "-0.1290,51.5030,-0.1260,51.5040"
            },
            "geometry": {
                "type": "Point",
                "coordinates": [-0.1275, 51.5034]
            }
        },
        {
            "type": "Feature",
            "properties": {
                "name": "Cambridge",
                "near": "Cambridge, Cambridgeshire",
                "bbox": "0.0686,52.2372,0.1846,52.1579"
            },
            "geometry": {
                "type": "Point",
                "coordinates": [0.1218, 52.2053]
            }
        }
    ]
}
""".data(using: .utf8)!

private let sampleGeoJSONWithoutNear = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "name": "Somewhere Remote"
            },
            "geometry": {
                "type": "Point",
                "coordinates": [-3.5, 55.0]
            }
        }
    ]
}
""".data(using: .utf8)!
