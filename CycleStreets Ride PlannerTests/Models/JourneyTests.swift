//
//  JourneyTests.swift
//  CycleStreets Ride PlannerTests
//

import Foundation
import Testing
@testable import CycleStreets_Ride_Planner

struct JourneyTests {

    // Journey/segment decoding from the real CycleStreets wire format is
    // covered by JourneyPlanDecoderTests — Journey/Segment here are plain
    // Codable value types with no bespoke decoding of their own.

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
