//
//  JourneyPlanDecoderTests.swift
//  Wheel RoutesTests
//

import Testing
import Foundation
@testable import Wheel_Routes

struct JourneyPlanDecoderTests {

    @Test func decodesRouteMarkerIntoJourney() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        #expect(journey.number == 123700734)
        #expect(journey.plan == .quietest)
        #expect(journey.lengthMetres == 6372)
        #expect(journey.timeSeconds == 1914)
        #expect(journey.segments.count == 2)
    }

    @Test func decodesSegmentFields() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        let first = journey.segments[0]
        #expect(first.name == "Senate House Hill")
        #expect(first.distanceMetres == 25)
        #expect(first.timeSeconds == 15)
        #expect(first.number == 1)
    }

    @Test func mapsEmptyTurnStringToNil() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        #expect(journey.segments[0].turn == nil)
    }

    @Test func preservesNonEmptyTurnInstruction() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        #expect(journey.segments[1].turn == "turn right")
    }

    @Test func parsesSpaceSeparatedPoints() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSON, requestedPlan: .balanced)
        let points = journey.segments[0].points
        #expect(points.count == 3)
        #expect(points[0].longitude == 0.11783)
        #expect(points[0].latitude == 52.20530)
        #expect(points[2].longitude == 0.11786)
        #expect(points[2].latitude == 52.20553)
    }

    @Test func fallsBackToRequestedPlanWhenPlanFieldUnrecognized() throws {
        let journey = try JourneyPlanDecoder.decode(sampleJSONWithMissingPlan, requestedPlan: .fastest)
        #expect(journey.plan == .fastest)
    }

    @Test func throwsWhenNoRouteMarkerPresent() {
        #expect(throws: (any Error).self) {
            try JourneyPlanDecoder.decode(sampleJSONWithNoRouteMarker, requestedPlan: .balanced)
        }
    }
}

/// Trimmed from a real captured `journey.json` response — field names,
/// string-typing, and the "@attributes" wrapper match the live API exactly.
private let sampleJSON = """
{
    "marker": [
        {
            "@attributes": {
                "itinerary": "123700734",
                "plan": "quietest",
                "length": "6372",
                "time": "1914",
                "type": "route"
            }
        },
        {
            "@attributes": {
                "name": "Senate House Hill",
                "distance": "25",
                "time": "15",
                "turn": "",
                "points": "0.11783,52.20530 0.11783,52.20541 0.11786,52.20553",
                "type": "segment"
            }
        },
        {
            "@attributes": {
                "name": "St Mary's Street",
                "distance": "60",
                "time": "16",
                "turn": "turn right",
                "points": "0.11786,52.20553 0.118,52.2055",
                "type": "segment"
            }
        }
    ],
    "waypoint": []
}
""".data(using: .utf8)!

private let sampleJSONWithMissingPlan = """
{
    "marker": [
        {
            "@attributes": {
                "itinerary": "1",
                "length": "100",
                "time": "60",
                "type": "route"
            }
        }
    ]
}
""".data(using: .utf8)!

private let sampleJSONWithNoRouteMarker = """
{
    "marker": [
        {
            "@attributes": {
                "name": "Orphan Segment",
                "distance": "10",
                "time": "5",
                "type": "segment"
            }
        }
    ]
}
""".data(using: .utf8)!
