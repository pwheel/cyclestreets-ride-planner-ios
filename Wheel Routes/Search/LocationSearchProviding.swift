//
//  LocationSearchProviding.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

/// Abstracts the Map screen's From/To location search behind a single
/// call, decoupled from `APIClientProtocol` (the CycleStreets network
/// client) — see docs/superpowers/specs/2026-08-08-improve-typeahead-design.md.
/// Not `@MainActor`-isolated: unlike a delegate-callback-based API, this is
/// a stateless, plain `async throws` call, matching `APIClientProtocol`'s
/// own style.
protocol LocationSearchProviding: Sendable {
    /// `near`, when non-nil, biases (doesn't filter) results toward that
    /// coordinate.
    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place]
}
