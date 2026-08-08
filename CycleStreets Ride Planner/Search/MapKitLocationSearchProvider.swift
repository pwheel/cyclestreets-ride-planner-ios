//
//  MapKitLocationSearchProvider.swift
//  CycleStreets Ride Planner
//

import MapKit

/// Wraps `MKLocalSearchCompleter`'s delegate API as a continuous
/// `AsyncStream`, and `MKLocalSearch` as a one-shot resolve call. See
/// `docs/superpowers/specs/2026-08-08-improve-typeahead-design.md` for why
/// this streams live rather than wrapping a single request/response.
@MainActor
final class MapKitLocationSearchProvider: NSObject, LocationSearchProviding {
    let suggestionsUpdates: AsyncStream<[SearchSuggestion]>
    private let continuation: AsyncStream<[SearchSuggestion]>.Continuation
    private let completer = MKLocalSearchCompleter()

    /// Replaced wholesale on every delegate update. A `resolve(_:)` call
    /// against a suggestion `id` from an older batch throws
    /// `.staleSuggestion` rather than resolving the wrong place.
    private var completionsByID: [String: MKLocalSearchCompletion] = [:]

    override init() {
        var continuation: AsyncStream<[SearchSuggestion]>.Continuation!
        self.suggestionsUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
        super.init()
        completer.delegate = self
    }

    func updateQuery(_ query: String) {
        completer.queryFragment = query
    }

    func updateRegion(_ region: MKCoordinateRegion?) {
        guard let region else { return }
        completer.region = region
    }

    func resolve(_ suggestion: SearchSuggestion) async throws -> Place {
        guard let completion = completionsByID[suggestion.id] else {
            throw LocationSearchError.staleSuggestion
        }
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else {
            throw LocationSearchError.noResult
        }
        return Place(mapItem: item)
    }
}

extension MapKitLocationSearchProvider: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completionsByID = [:]
        let suggestions = completer.results.map { completion -> SearchSuggestion in
            let id = UUID().uuidString
            completionsByID[id] = completion
            return SearchSuggestion(id: id, title: completion.title, subtitle: completion.subtitle)
        }
        continuation.yield(suggestions)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // A live suggestions failure mid-type isn't user-facing — matches
        // how the old search(query:) silently swallowed a superseded
        // keystroke's cancellation. Yield empty rather than surfacing an
        // error for what is often just a transient/offline blip.
        continuation.yield([])
    }
}
