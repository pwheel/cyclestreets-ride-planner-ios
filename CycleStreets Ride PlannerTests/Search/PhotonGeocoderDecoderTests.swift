//
//  PhotonGeocoderDecoderTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
@testable import CycleStreets_Ride_Planner

struct PhotonGeocoderDecoderTests {

    @Test func decodesFeatureIntoPlaceWithFullAddress() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleWithFullAddress)
        #expect(places.count == 1)
        #expect(places[0].name == "Cambridge")
        #expect(places[0].near == "Cambridge, Cambridgeshire, England, United Kingdom")
        #expect(places[0].coordinate.longitude == 0.1186637)
        #expect(places[0].coordinate.latitude == 52.2055314)
    }

    @Test func fallsBackToStreetWhenNameMissing() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleMissingName)
        #expect(places[0].name == "Trumpington Street")
    }

    @Test func fallsBackToUnknownLocationWhenNameAndStreetMissing() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleMissingNameAndStreet)
        #expect(places[0].name == "Unknown location")
    }

    @Test func nearFallsBackToDistrictWhenCityMissing() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleCityLevelResult)
        #expect(places[0].near == "Cambridgeshire, England, United Kingdom")
    }

    @Test func handlesMissingAddressFieldsEntirely() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleNoAddressFields)
        #expect(places[0].near == nil)
    }

    @Test func skipsFeatureWithMalformedCoordinates() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleMalformedCoordinates)
        #expect(places.isEmpty)
    }

    @Test func placesHaveDistinctIdentifiers() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleTwoFeatures)
        #expect(places[0].id != places[1].id)
    }
}

private let sampleWithFullAddress = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "osm_type": "N",
                "osm_id": 20971094,
                "name": "Cambridge",
                "city": "Cambridge",
                "county": "Cambridgeshire",
                "state": "England",
                "country": "United Kingdom",
                "postcode": "CB2 3NR"
            },
            "geometry": { "type": "Point", "coordinates": [0.1186637, 52.2055314] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleMissingName = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "street": "Trumpington Street",
                "city": "Cambridge",
                "country": "United Kingdom"
            },
            "geometry": { "type": "Point", "coordinates": [0.1218, 52.2001] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleMissingNameAndStreet = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": { "country": "United Kingdom" },
            "geometry": { "type": "Point", "coordinates": [0.1, 52.2] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleCityLevelResult = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "name": "Cambridge",
                "district": "Cambridgeshire",
                "state": "England",
                "country": "United Kingdom"
            },
            "geometry": { "type": "Point", "coordinates": [0.1391537, 52.1975846] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleNoAddressFields = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": { "name": "Null Island" },
            "geometry": { "type": "Point", "coordinates": [0.0, 0.0] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleMalformedCoordinates = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": { "name": "Bad Coordinates" },
            "geometry": { "type": "Point", "coordinates": [0.0] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleTwoFeatures = """
{
    "type": "FeatureCollection",
    "features": [
        { "type": "Feature", "properties": { "name": "A" }, "geometry": { "type": "Point", "coordinates": [0.0, 1.0] } },
        { "type": "Feature", "properties": { "name": "B" }, "geometry": { "type": "Point", "coordinates": [2.0, 3.0] } }
    ]
}
""".data(using: .utf8)!
