//
//  ItineraryViewModelTests.swift
//  Wheel RoutesTests
//

import Foundation
import Testing
@testable import Wheel_Routes

struct ItineraryViewModelTests {

    @Test func testFormatsDistanceMetric() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: true)
        #expect(vm.totalDistance == "4.2 km")
    }

    @Test func testFormatsDistanceImperial() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: false)
        #expect(vm.totalDistance == "2.6 mi")
    }

    @Test func testFormatsTime() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: true)
        #expect(vm.totalTime == "18 min")
    }

    @Test func testSegmentRowHasTurnInstruction() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: true)
        #expect(vm.rows[0].instruction == "Straight on")
        #expect(vm.rows[0].streetName == "High Street")
    }
}

private func makeJourney() -> Journey {
    Journey(
        number: 1, plan: .balanced, lengthMetres: 4200, timeSeconds: 1080,
        segments: [
            Segment(number: 1, name: "High Street", distanceMetres: 450,
                    timeSeconds: 120, turn: "Straight on", points: [])
        ]
    )
}
