# Design: Replace CycleStreets typeahead/geocoder with Apple MapKit

> Addresses GitHub issue #19 — "Replace CycleStreets typeahead/geocoder with
> Apple MapKit for search." SPEC.md's "Known limitations" section currently
> lists "switchable geocoder provider (CycleStreets vs MapKit, flag-based)"
> as a roadmap item from `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`;
> this supersedes that framing — the outcome is a straight replacement, not a
> flag-based dual-provider system (see "Why straight replacement" below).

## Summary

The Map screen's From/To search (`MapViewModel.searchTextChanged`/`search`,
backed today by `Endpoints.geocode` against CycleStreets' v2 geocoder) is
replaced outright by Apple MapKit's `MKLocalSearchCompleter` +
`MKLocalSearch`. This is safe because CycleStreets' journey-planning
endpoints (`Endpoints.journeyPlan`/`journeyReload`) only ever consume raw
`lon,lat` — the geocoder has no other coupling to routing, so swapping its
provider is isolated to the search flow.

Three decisions, made with the user before this design:

1. **Straight replacement**, not a flag-based dual-provider system. The
   CycleStreets geocoder path (`Endpoints.geocode`, `GeocoderDecoder`,
   `APIClientProtocol.geocode`) is deleted, not kept behind a toggle.
2. **True live typeahead**, not a swapped-in single request/response call.
   `MKLocalSearchCompleter`'s delegate stream drives `searchResults`
   directly as the user types — no manual debounce.
3. **Location-biased results** when the device's location is already
   authorized (non-prompting check) — unbiased otherwise. Opening search
   never itself triggers the location permission prompt.

## Why straight replacement, not a flag

The roadmap doc that originally raised this (linked above) flagged real
open questions about a dual-provider approach: where geocoding
conceptually lives, where a toggle would live, and — most concretely — that
two live search implementations means `MapViewModelTests` needs coverage
for both, doubling the test/maintenance surface for a benefit ("CycleStreets
might still win for some UK-specific queries") that's speculative rather
than observed. The issue's own suggested next step (a throwaway
CycleStreets-vs-MapKit comparison) was about *deciding* this, not something
this design routes around — the user made the call directly: MapKit
replaces CycleStreets outright.

## Why live streaming, not a wrapped single call

`MKLocalSearchCompleter` is delegate-based and, by design, can call back
multiple times for one query as it refines results (fast local matches
first, more complete results shortly after). An alternative considered was
wrapping it in a single continuation per query (matching how
`LocationService.currentLocation()` wraps `CLLocationManager`'s
delegate), keeping today's 300ms debounce untouched — a smaller diff, but
it would mean waiting for `completer.isSearching == false` before showing
anything, closer to today's submit-and-wait feel than true typeahead.

Since `MKLocalSearchCompleter` has no rate limit to protect against (unlike
`MKLocalSearch`, which does) and is designed exactly for live-as-you-type
use, forwarding every keystroke straight to `queryFragment` and streaming
results back live is both the simpler mapping onto its actual API contract
and the UX the user asked for. This removes `MapViewModel`'s manual debounce
machinery (`searchDebounceMilliseconds`, the debounce `Task`) entirely.

## Components

### `Search/LocationSearchProviding.swift` (new)

```swift
struct SearchSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

@MainActor
protocol LocationSearchProviding: AnyObject {
    var suggestionsUpdates: AsyncStream<[SearchSuggestion]> { get }
    func updateQuery(_ query: String)
    func updateRegion(_ region: MKCoordinateRegion?)
    func resolve(_ suggestion: SearchSuggestion) async throws -> Place
}
```

`SearchSuggestion` deliberately holds no coordinate — `MKLocalSearchCompletion`
(what backs a live suggestion) has no public initializer, so it can't be
stored on or reconstructed from a plain model usable in tests. Resolving to
an actual `Place` is a separate, explicit step (`resolve`), run only when
the user acts on a suggestion (tap to select, tap bookmark to save) — never
for the full list of live suggestions, which would mean one `MKLocalSearch`
call per keystroke per row instead of the free, unlimited completer.

### `Search/MapKitLocationSearchProvider.swift` (new)

Real implementation, `NSObject` + `MKLocalSearchCompleterDelegate`:

```swift
enum LocationSearchError: Error {
    /// `resolve` was called with a suggestion `id` from a results batch
    /// that's since been replaced by a newer one.
    case staleSuggestion
    /// The resolved `MKLocalSearch` returned no map items.
    case noResult
}

final class MapKitLocationSearchProvider: NSObject, LocationSearchProviding {
    let suggestionsUpdates: AsyncStream<[SearchSuggestion]>
    private let continuation: AsyncStream<[SearchSuggestion]>.Continuation
    private let completer = MKLocalSearchCompleter()
    private var completionsByID: [String: MKLocalSearchCompletion] = [:]

    override init() {
        var continuation: AsyncStream<[SearchSuggestion]>.Continuation!
        self.suggestionsUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
        super.init()
        completer.delegate = self
    }

    func updateQuery(_ query: String) { completer.queryFragment = query }

    /// `nil` leaves `completer.region` at its Apple-supplied default (the
    /// whole world), which is effectively unbiased.
    func updateRegion(_ region: MKCoordinateRegion?) {
        guard let region else { return }
        completer.region = region
    }

    func resolve(_ suggestion: SearchSuggestion) async throws -> Place {
        guard let completion = completionsByID[suggestion.id] else {
            throw LocationSearchError.staleSuggestion
        }
        let response = try await MKLocalSearch(request: .init(completion: completion)).start()
        guard let item = response.mapItems.first else { throw LocationSearchError.noResult }
        return Place(mapItem: item)
    }
}

extension MapKitLocationSearchProvider: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completionsByID = [:]
        let suggestions = completer.results.map { completion in
            let id = UUID().uuidString
            completionsByID[id] = completion
            return SearchSuggestion(id: id, title: completion.title, subtitle: completion.subtitle)
        }
        continuation.yield(suggestions)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Live suggestions failing mid-type isn't user-facing (matches how
        // `search(query:)` today silently swallows cancellation from a
        // superseded keystroke) — yield empty rather than surfacing an error.
        continuation.yield([])
    }
}
```

`completionsByID` is replaced wholesale on every update, so a suggestion's
`id` is only valid against the results it was issued with. If a `resolve`
call races a fresher update (the id vanishes from the map), it throws
`.staleSuggestion` — surfaced the same way as any other resolve failure (see
Error handling). This is an intentionally accepted edge case: it requires
tapping a row in the narrow window between the list changing under it,
which SwiftUI's synchronous re-render makes very unlikely in practice.

A `Place(mapItem:)` initializer is added to `Place`: `name` from
`mapItem.name`, `near` from the placemark's locality/administrative area
(mirroring the existing `name`+`near` split used for CycleStreets results),
`coordinate` from `mapItem.placemark.coordinate`, `id` a fresh `UUID()`.

Joins `LocationService` in SPEC.md's "build-verify-only" test-coverage
bucket — a delegate-based wrapper around a concrete Apple type, not
exercisable via `xcodebuild test` on a simulator.

### `App/AppEnvironment.swift`

New environment key, matching `.locationService`:

```swift
extension EnvironmentValues {
    var locationSearchProvider: any LocationSearchProviding {
        get { self[LocationSearchProviderKey.self] }
        set { self[LocationSearchProviderKey.self] = newValue }
    }
}
```
Default value `MapKitLocationSearchProvider()`.

### `MapViewModel`

- `searchResults: [Place]` → `searchResults: [SearchSuggestion] = []`.
- Removed: `searchDebounceMilliseconds`, `searchDebounceTask`, `search(query:)`.
- `init` gains a third dependency, `searchProvider: any LocationSearchProviding`,
  alongside the existing `apiClient`/`locationService` parameters.
- `searchTextChanged(_ text: String)` becomes a thin, synchronous forward:
  ```swift
  func searchTextChanged(_ text: String) {
      guard !text.isEmpty else { searchResults = []; return }
      searchProvider.updateQuery(text)
  }
  ```
- `init` starts a long-lived `Task` consuming `searchProvider.suggestionsUpdates`
  and assigning each batch to `searchResults`.
- `init` also, if `locationService.isAuthorized`, fires a detached `Task` to
  fetch `currentLocation()` and call `searchProvider.updateRegion(_:)` with a
  generous ~1° (roughly 100km) span around it — wide enough to bias toward
  "your general area" without acting as a hard filter, unlike the tight
  0.05°-span zoom `MapView` uses when centering on a single selected place.
  Best-effort and non-blocking: search remains usable immediately even
  before/without a location fix, just unbiased until one lands.
- New method, used by both tap-to-select and bookmark-to-save:
  ```swift
  func resolve(_ suggestion: SearchSuggestion) async -> Place? {
      do { return try await searchProvider.resolve(suggestion) }
      catch { errorMessage = "Couldn't get details for that result. Please try again."; return nil }
  }
  ```

### `MapView`

- `.onSubmit { Task { await vm.search(query: searchText) } }` is removed —
  there's no `search(query:)` to call anymore, and it has no live
  replacement to fall back to since results are already streaming as the
  user types.
- `resultsList`'s `List(vm.searchResults)` now iterates `[SearchSuggestion]`,
  rendering `suggestion.title`/`suggestion.subtitle` where it rendered
  `place.name`/`place.near` before.
- `selectPlace(_ place: Place)` becomes `selectSuggestion(_ suggestion: SearchSuggestion)`:
  resolves first, then runs the same logic as today (clear search text/results,
  advance the From→To picker, animate the camera, call
  `vm.selectPlace(_:as:)`) — the camera-update line moves inside the `Task`
  since it needs the resolved coordinate, which isn't available until after
  `resolve` returns:
  ```swift
  private func selectSuggestion(_ suggestion: SearchSuggestion) {
      searchText = ""
      vm.searchResults = []
      let role = selectingFor
      if role == .from { selectingFor = .to }
      Task {
          guard let place = await vm.resolve(suggestion) else { return }
          withAnimation {
              updateCamera(to: MKCoordinateRegion(
                  center: place.clCoordinate,
                  span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
              ))
          }
          await vm.selectPlace(place, as: role)
          if vm.fromPlace != nil && vm.toPlace != nil { isSearchFieldFocused = false }
      }
  }
  ```
- The bookmark button's action becomes async too:
  ```swift
  Button {
      Task {
          guard let place = await vm.resolve(suggestion) else { return }
          savedLocationsVM.save(name: place.name, coordinate: place.coordinate)
          isPresentingLocationSavedConfirmation = true
      }
  } label: { Image(systemName: "bookmark") }
  ```
- The "Current Location" pinned row (`useCurrentLocation()`) is untouched —
  it never went through `searchResults`/geocoding and still doesn't.

### Removed entirely

`Endpoints.geocode`, `Networking/GeocoderDecoder.swift` (+ its test file
`GeocoderDecoderTests`), `geocode(query:)` from `APIClientProtocol`/
`APIClient`, and `MockAPIClient`'s geocode-related fields
(`placesToReturn`, `geocodeQueriesReceived`, `geocodeDelayMilliseconds`).

## Error handling

- **Live suggestions failing** (`completer(_:didFailWithError:)`): silent —
  yields an empty list, no `errorMessage`. Matches today's treatment of a
  superseded/cancelled search as a non-error.
- **Resolve failing** (tap-to-select or tap-to-bookmark): sets
  `errorMessage` to "Couldn't get details for that result. Please try
  again." — a discrete, user-initiated action, so unlike live suggestions
  this is worth surfacing (mirrors `useCurrentLocation`'s generic-failure
  handling).
- **Region bias fetch failing** (init-time, best-effort): silent — search
  proceeds unbiased. Not user-initiated, so no error surface; matches the
  "never prompt/error for background convenience fetches" spirit of
  `isLocationAuthorized`'s non-prompting design.

## Testing

- `Search/MockLocationSearchProvider.swift` (new, test target): conforms to
  `LocationSearchProviding`; records `updateQuery`/`updateRegion` calls;
  exposes its own stream continuation so tests can push suggestion batches
  on demand; `resolveResult: Result<Place, Error>` (or per-id dictionary)
  stubs `resolve`.
- `MapViewModelTests`: the debounce-specific tests
  (`testSearchTextChangedDebouncesAndSearches`,
  `testSearchTextChangedCancelsPendingSearchOnRapidTyping`,
  `testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded`,
  `testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires`) are
  removed since there's no debounce left to test. New coverage:
  query-forwarding (`updateQuery` called with the typed text),
  stream-to-`searchResults` propagation, `resolve` success/failure
  (including the error-message text), and region-bias gating
  (`updateRegion` called when `MockLocationService.isAuthorized == true`,
  not called otherwise). `testSearchTextChangedWithEmptyQueryClearsResultsImmediately`
  is kept, adapted to the new signature.
- `MapKitLocationSearchProvider` and the `MapView` wiring changes (list
  rendering, async button actions) are build-verify-only, per the existing
  convention for pure-SwiftUI-wiring and Apple-API-delegate-wrapper code.

## Out of scope

- Any change to `useCurrentLocation(as:)`/the "Current Location" row —
  untouched, doesn't go through search.
- A CycleStreets-vs-MapKit comparison step — superseded by the direct
  replacement decision; not performed as separate throwaway work.
- Reverse geocoding for anything beyond what `MKLocalSearch` already returns
  in a resolved `MKMapItem`.
- Editable saved-location names (separate roadmap item, unrelated).
