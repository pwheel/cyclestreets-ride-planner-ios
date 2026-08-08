//
//  LocationSearchProviding.swift
//  CycleStreets Ride Planner
//

import Foundation
import MapKit

/// A single live typeahead suggestion — title/subtitle only, no coordinate.
/// `MKLocalSearchCompletion` (what a real suggestion is backed by) has no
/// public initializer, so this plain model is what crosses into
/// `MapViewModel`/tests; resolving a specific suggestion to a `Place` is a
/// separate, explicit step (`LocationSearchProviding.resolve(_:)`).
struct SearchSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

enum LocationSearchError: Error, Equatable {
    /// `resolve` was called with a suggestion `id` from a results batch
    /// that's since been replaced by a newer one.
    case staleSuggestion
    /// The resolved `MKLocalSearch` returned no map items.
    case noResult
}

/// Isolated to the main actor for the same reason as `LocationServiceProtocol`:
/// its real implementation wraps a delegate-based Apple API whose callbacks
/// arrive on the actor the object was created on.
@MainActor
protocol LocationSearchProviding: AnyObject, Sendable {
    /// Live suggestion batches, updated continuously as `updateQuery(_:)` is
    /// called and the underlying search refines its results. Never finishes.
    var suggestionsUpdates: AsyncStream<[SearchSuggestion]> { get }

    /// Forwards the current search text. Call on every keystroke — no
    /// debounce is needed or expected here (see the design doc's rationale).
    func updateQuery(_ query: String)

    /// Biases subsequent suggestions toward the given region. Passing `nil`
    /// leaves any existing bias in place — there is no "clear bias" case in
    /// this app's usage (see `MapViewModel`, Task 3).
    func updateRegion(_ region: MKCoordinateRegion?)

    /// Resolves a specific suggestion to a coordinate-bearing `Place`. Only
    /// called for a suggestion the user has actually acted on (tap to
    /// select, tap to bookmark) — never for a whole live results batch.
    func resolve(_ suggestion: SearchSuggestion) async throws -> Place
}
