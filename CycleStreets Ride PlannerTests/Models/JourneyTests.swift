//
//  JourneyTests.swift
//  CycleStreets Ride PlannerTests
//

import Foundation
import Testing
@testable import CycleStreets_Ride_Planner

struct JourneyTests {

    @Test func testJourneyDecodesFromJSON() throws {
        let json = """
        {
          "journey": {
            "number": 12345678,
            "plan": "balanced",
            "lengthMetres": 4200,
            "timeSeconds": 1080,
            "segments": [
              {
                "number": 1,
                "name": "High Street",
                "distanceMetres": 450,
                "timeSeconds": 120,
                "turn": "Straight on",
                "points": [
                  {"longitude": -0.1278, "latitude": 51.5074},
                  {"longitude": -0.1280, "latitude": 51.5080}
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(JourneyResponse.self, from: json)
        #expect(response.journey.number == 12345678)
        #expect(response.journey.plan == .balanced)
        #expect(response.journey.segments.count == 1)
        #expect(response.journey.segments[0].name == "High Street")
        #expect(response.journey.segments[0].points.count == 2)
    }

    @Test func testSegmentFormattedDistance() {
        let segment = Segment(
            number: 1, name: "Mill Road",
            distanceMetres: 1500, timeSeconds: 360,
            turn: "Turn left",
            points: []
        )
        #expect(segment.formattedDistance(metric: true) == "1.5 km")
        #expect(segment.formattedDistance(metric: false) == "0.9 mi")
    }

}
