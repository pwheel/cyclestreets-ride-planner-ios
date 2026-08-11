# Design: Replace CycleStreets typeahead/geocoder with Photon (OSM)

> Addresses GitHub issue #19 — "Replace CycleStreets typeahead/geocoder ...
> for search." Originally scoped around Apple MapKit (`MKLocalSearchCompleter`/
> `MKLocalSearch`); **revised mid-implementation** (after two tasks of the
> MapKit-based plan had already landed) once it became clear Apple's MapKit
> terms restrict search-result usage to Apple's own map, which conflicts with
> this app's existing OSM-tile rendering path (`docs/superpowers/specs/2026-07-26-map-tile-providers-design.md`).
> The provider is now [Photon](https://photon.komoot.io) — a public,
> OSM-data-backed geocoder — via its free demo API. Everything below
> supersedes the MapKit-specific sections of the original version of this
> document; the non-provider-specific decisions (straight replacement, no
> flag) still stand.

## Summary

The Map screen's From/To search (`MapViewModel.searchTextChanged`/`search`,
backed today by `Endpoints.geocode` against CycleStreets' v2 geocoder) is
replaced outright by [Photon](https://photon.komoot.io)'s public demo API
(`GET https://photon.komoot.io/api/`). Safe for the same reason as the
original design: CycleStreets' journey-planning endpoints only ever consume
raw `lon,lat`, so the geocoder has no other coupling to routing.

Decisions carried over from the original design:

1. **Straight replacement**, not a flag-based dual-provider system. The
   CycleStreets geocoder path (`Endpoints.geocode`, `GeocoderDecoder`,
   `APIClientProtocol.geocode`) is deleted, not kept behind a toggle.
2. **Location-biased results** when the device's location is already
   authorized (non-prompting check) — unbiased otherwise. Opening search
   never itself triggers the location permission prompt.

Decisions that changed with the Photon pivot:

3. **A single debounced request/response call, not a live stream.** Unlike
   `MKLocalSearchCompleter` (free, no rate limit, designed for live typing),
   Photon's public demo instance's policy is "reasonable use only —
   extensive usage will be throttled or completely banned," with no
   documented request budget. The original design's justification for
   dropping the debounce doesn't hold for a shared community-run API — the
   debounce comes back.
4. **No two-phase suggestion/resolve split.** Photon's response already
   returns a full place per result — name, address components, and
   coordinates — in one call (confirmed live: `GET /api/?q=cambridge&limit=5`
   returns `properties.name`/`city`/`county`/`state`/`country`/`postcode`
   and `geometry.coordinates`). `MKLocalSearchCompletion`'s "no coordinate,
   no public initializer" constraint, which the two-phase design existed to
   work around, doesn't apply here — `search(query:)` returns `[Place]`
   directly, same shape as the original CycleStreets geocoder.
5. **OSM/ODbL attribution**, since Photon's data is OSM-derived. Per the
   user: shown in `SettingsView`'s existing "About" section, not inline
   near the search UI.

## What survives from Tasks 1–2 of the original plan, what doesn't

Two tasks of the MapKit-based plan were already implemented and committed
before this pivot. Rather than revert that history, the revised
implementation plan supersedes the obsolete pieces via new commits, the
same way the original plan already deleted the CycleStreets geocoder in a
later task:

- **Kept:** the general shape of decoupling search from `APIClientProtocol`
  into its own `LocationSearchProviding` protocol, injected via
  `EnvironmentValues` the same way as `.apiClient`/`.locationService`. The
  `Place(mapItem:)` MapKit-specific initializer is *not* reused (Photon
  doesn't produce `MKMapItem`s) but the general "extract geocoding out of
  the CycleStreets client" direction the roadmap doc originally raised is
  still the right call.
- **Deleted/replaced:** `SearchSuggestion` (no longer needed — Photon
  returns full `Place`s), the `AsyncStream`/`updateQuery`/`updateRegion`/
  `resolve` shape of `LocationSearchProviding` (replaced by a single
  `search(query:near:)` call), `MapKitLocationSearchProvider.swift`
  (deleted outright), `Place(mapItem:)` (MapKit-specific, deleted).

## Components

### `Search/LocationSearchProviding.swift` (revised)

```swift
protocol LocationSearchProviding: Sendable {
    /// `near`, when provided, biases (not filters) results toward that
    /// coordinate — a suggestion, not a hard requirement, per Photon's
    /// `lat`/`lon`/`zoom` params.
    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place]
}
```

No longer `@MainActor`/`AnyObject` — unlike the MapKit version (a
stateful delegate-callback wrapper that had to live on the actor
`CLLocationManager`-style APIs deliver callbacks on), this is a stateless,
plain `async throws` call over HTTP, matching `APIClientProtocol`'s
existing style exactly (which also isn't `@MainActor`-isolated).
`SearchSuggestion` and `LocationSearchError` are deleted — Photon results
resolve to a `Place` in one step, so there's no "suggestion vs. resolved
place" distinction and nothing can go stale between two calls.

### `Search/PhotonEndpoint.swift` (new)

Pure URL-building, mirroring `Networking/Endpoints.swift`'s existing style
(and fully unit-testable the same way `EndpointsTests`-style coverage
already tests `Endpoints.geocode`/`journeyPlan`):

```swift
enum PhotonEndpoint {
    private static let base = "https://photon.komoot.io/api/"

    static func search(query: String, near coordinate: CLLocationCoordinate2D?) throws -> URL {
        var c = URLComponents(string: base)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "6"),
        ]
        if let coordinate {
            items.append(URLQueryItem(name: "lat", value: "\(coordinate.latitude)"))
            items.append(URLQueryItem(name: "lon", value: "\(coordinate.longitude)"))
        }
        c.queryItems = items
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }
}
```

`limit=6` matches the result count the original CycleStreets geocoder
requested (`results=6`), for a consistent list length in the UI. No
`zoom`/`location_bias_scale` override — Photon's documented defaults
(`zoom=12`, `location_bias_scale=0.4`) are a reasonable "prefer nearby
without hard-filtering far matches" behavior out of the box.

### `Search/PhotonGeocoderDecoder.swift` (new)

Pure decode function, mirroring `Networking/GeocoderDecoder.swift`'s
existing style and equally unit-testable:

```swift
enum PhotonGeocoderDecoder {
    private struct RawResponse: Decodable {
        let features: [RawFeature]
    }

    private struct RawFeature: Decodable {
        let properties: RawProperties
        let geometry: RawGeometry
    }

    private struct RawProperties: Decodable {
        let name: String?
        let street: String?
        let city: String?
        let district: String?
        let county: String?
        let state: String?
        let country: String?
    }

    private struct RawGeometry: Decodable {
        let coordinates: [Double]
    }

    static func decode(_ data: Data) throws -> [Place] {
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        return raw.features.compactMap { feature -> Place? in
            guard feature.geometry.coordinates.count == 2 else { return nil }
            let coordinate = Coordinate(
                longitude: feature.geometry.coordinates[0],
                latitude: feature.geometry.coordinates[1]
            )
            let props = feature.properties
            let name = props.name ?? props.street ?? "Unknown location"
            let nearParts = [props.city ?? props.district, props.county, props.state, props.country]
                .compactMap { $0 }
            let near = nearParts.isEmpty ? nil : nearParts.joined(separator: ", ")
            return Place(id: UUID().uuidString, name: name, near: near, coordinate: coordinate)
        }
    }
}
```

Field notes, confirmed against live responses: `properties.name` is present
for named places (cities, POIs) but absent for some pure address results,
where `street` is the closer analog — hence the fallback chain, matching
the spirit of `GeocoderDecoder`'s handling of CycleStreets' own optional
`near`. `near` prefers `city` (falling back to `district` when a result is
itself a city/region with no separate city field, e.g. Cambridge's own
top-level city result) then broadens through `county`/`state`/`country`,
skipping whichever of those Photon omits for a given result — mirroring how
CycleStreets' single optional `near` string worked, just assembled from
more granular fields.

### `Search/PhotonLocationSearchProvider.swift` (new)

Thin async wrapper combining the two above with `URLSession`, the only
piece that isn't unit-testable without network access (mirrors
`APIClient`'s own untested-directly `session.data(from:)` calls — the
already-established pattern in this codebase for the actual network hop,
with `PhotonEndpoint`/`PhotonGeocoderDecoder` carrying the real test
coverage):

```swift
final class PhotonLocationSearchProvider: LocationSearchProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place] {
        let url = try PhotonEndpoint.search(query: query, near: coordinate)
        let (data, _) = try await session.data(from: url)
        return try PhotonGeocoderDecoder.decode(data)
    }
}
```

### `App/AppEnvironment.swift`

Same shape as the (already-landed) Task 2, default value changes:

```swift
private struct LocationSearchProviderKey: EnvironmentKey {
    static let defaultValue: any LocationSearchProviding = PhotonLocationSearchProvider()
}
```

### `MapViewModel`

Closer to the *original* (pre-MapKit) shape than the MapKit design was —
the debounce comes back essentially unchanged:

- `searchResults: [Place]` — **unchanged type**, no `SearchSuggestion`.
- `searchDebounceMilliseconds: UInt64 = 300` and `searchDebounceTask` —
  **restored**, same as the pre-MapKit code.
- `init` gains a third dependency, `searchProvider: any LocationSearchProviding`
  (same DI shape Task 3 was always going to add — this part of the original
  design didn't change).
- `search(query:) async` — restored, now calling the new provider and
  passing a cached bias coordinate:
  ```swift
  func search(query: String) async {
      guard !query.isEmpty else { searchResults = []; return }
      do {
          searchResults = try await searchProvider.search(query: query, near: biasCoordinate)
      } catch {
          guard !Task.isCancelled else { return }
          errorMessage = error.localizedDescription
      }
  }
  ```
- `searchTextChanged(_:)` — restored to the original debounce-`Task`
  implementation, unchanged from before the MapKit detour.
- `init` still does the location-bias fetch from the MapKit design, but
  simplified: instead of pushing a region into a stateful provider, it
  caches the coordinate on `self` for `search(query:)` to pass per call:
  ```swift
  private var biasCoordinate: CLLocationCoordinate2D?
  ```
  populated by the same best-effort, non-blocking, `isAuthorized`-gated
  `Task` as before (see the original design's rationale for why this never
  prompts).
- **No `resolve(_:)` method** — deleted. Nothing needs a second call
  anymore; a `Place` from `searchResults` is already complete.

### `MapView`

Much closer to today's (pre-feature) code than the MapKit version was:

- `.onSubmit { Task { await vm.search(query: searchText) } }` —
  **restored** (immediate, non-debounced search on explicit submit,
  exactly as it works today).
- `resultsList`'s `List(vm.searchResults)` — **unchanged**, still iterates
  `[Place]`, still renders `place.name`/`place.near`.
- `selectPlace(_ place: Place)` — **unchanged**, no resolve step, no
  `selectSuggestion` rename.
- The bookmark button's action — **unchanged**, still synchronous
  (`savedLocationsVM.save(name: place.name, coordinate: place.coordinate)`
  directly), no `Task`/resolve wrapping needed.
- The "Current Location" pinned row — unaffected, as before.

In other words: of the `MapView` changes the MapKit design required, only
the dependency-injection plumbing (new `locationSearchProvider` init
parameter, threaded through from `RootView`) survives. The UI-facing
behavior changes are gone because Photon's single-call shape needs none of
them.

### `SettingsView` — OSM attribution

New rows in the existing "About" section (`Features/Settings/SettingsView.swift`),
matching the existing `Link` style used for the CycleStreets website/GPL
license:

```swift
Link("OpenStreetMap data (search)", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
Link("Photon geocoder", destination: URL(string: "https://photon.komoot.io")!)
```

Placed in Settings rather than inline near the search results, per the
user's explicit choice — consistent with how the app already links out to
licensing/attribution info (CycleStreets website, GPL) from that same
section rather than surfacing it contextually elsewhere.

### Removed entirely

Same as the original design: `Endpoints.geocode`, `Networking/GeocoderDecoder.swift`
(+ `GeocoderDecoderTests`), `geocode(query:)` from `APIClientProtocol`/
`APIClient`, `MockAPIClient`'s geocode-related fields. Additionally now:
`SearchSuggestion`, `LocationSearchError`, `Place(mapItem:)`,
`MapKitLocationSearchProvider.swift` — all MapKit-specific, all obsolete.

## Error handling

- **Search failing**: sets `errorMessage`, exactly as the original
  CycleStreets-backed `search(query:)` did — ignoring `Task.isCancelled`
  so a superseded in-flight request from a stale keystroke isn't
  user-facing (same rationale as before, now doubly relevant since a
  cancelled debounced request is the common case, not an edge case).
- **Bias-coordinate fetch failing** (init-time, best-effort): silent —
  search proceeds unbiased. Unchanged rationale from the original design.

## Testing

- `PhotonEndpoint`/`PhotonGeocoderDecoder` are fully unit-tested, pure
  functions — no network, no mocking, mirroring `EndpointsTests`-style
  coverage and `GeocoderDecoderTests` exactly (URL query-item assertions;
  decode assertions against realistic fixture JSON, including a result
  missing `name`/`city` to exercise the fallback chains).
- `Search/MockLocationSearchProvider.swift` (test double, replacing the
  MapKit-shaped one from the superseded Task 3 groundwork): conforms to
  the new single-method protocol — `queriesReceived: [(String, CLLocationCoordinate2D?)]`,
  `resultsToReturn: [Place]`, `errorToThrow: Error?`. Much simpler than the
  stream-based mock the MapKit design needed.
- `MapViewModelTests`: restores the original pre-MapKit debounce test
  suite almost verbatim (`testSearchTextChangedDebouncesAndSearches`,
  `testSearchTextChangedCancelsPendingSearchOnRapidTyping`,
  `testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires`,
  `testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded`,
  `testSearchTextChangedWithEmptyQueryClearsResultsImmediately`), now
  against `MockLocationSearchProvider` instead of `MockAPIClient`. New
  coverage: bias-coordinate gating (`search` called with a non-nil `near`
  when `MockLocationService.isAuthorized == true`, `nil` otherwise).
- `PhotonLocationSearchProvider` itself (the `URLSession` hop) joins
  `APIClient`'s existing untested-directly network call — not a new gap,
  the same shape of gap this codebase already accepts for `APIClient`.
- `MapView`'s wiring changes (only the new init parameter) are
  build-verify-only, same convention as always for pure DI plumbing.

## Out of scope

- Any change to `useCurrentLocation(as:)`/the "Current Location" row.
- Self-hosting Photon, or any fallback if the public demo instance is
  unavailable/throttled — accepted risk of using a free public demo,
  matching the same trade-off already accepted for Thunderforest/CyclOSM's
  free tiers elsewhere in this app.
- Editable saved-location names (separate roadmap item, unrelated).
- A CycleStreets-vs-Photon side-by-side comparison — not performed, same
  reasoning as the original design's straight-replacement decision.
