//
//  ItineraryViewModel.swift
//  Wheel Routes
//

import Foundation

struct SegmentRow: Identifiable {
    let id: Int
    let streetName: String
    let instruction: String
    let distance: String
    let duration: String
}

final class ItineraryViewModel {
    let journey: Journey
    let rows: [SegmentRow]
    let totalDistance: String
    let totalTime: String

    init(journey: Journey, useMetric: Bool) {
        self.journey = journey
        self.totalDistance = journey.formattedDistance(metric: useMetric)
        self.totalTime = journey.formattedDuration()
        self.rows = journey.segments.map { seg in
            SegmentRow(
                id: seg.id,
                streetName: seg.name,
                instruction: seg.turn ?? "Continue",
                distance: seg.formattedDistance(metric: useMetric),
                duration: "\(seg.timeSeconds / 60) min"
            )
        }
    }
}
