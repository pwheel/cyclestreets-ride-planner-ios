# Replace CycleStreets typeahead/geocoder with Photon — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision note:** This plan replaces an earlier MapKit-based version of
> itself. Two tasks of that version already landed (commits `59392fe`,
> `d95b31d` on this branch) before the pivot — see
> `docs/superpowers/specs/2026-08-08-improve-typeahead-design.md` for why
> (Apple's MapKit terms restrict search-result usage to Apple's own map,
> which conflicts with this app's existing OSM-tile rendering). Rather than
> revert that history, this plan's Task 1 supersedes it via new commits, the
> same way Task 3 below deletes the CycleStreets geocoder outright. Do not
> treat any "Task N: complete" ledger entry from before this revision as
> applying to the task numbering below — it refers to the superseded plan.

**Goal:** Replace the CycleStreets v2 geocoder backing the Map screen's From/To search with [Photon](https://photon.komoot.io) (a public, OSM-data-backed geocoder), restoring the debounced single-call search architecture the (superseded) MapKit version had removed.

**Architecture:** `LocationSearchProviding` (already introduced, protocol shape now simplified) exposes one method, `search(query:near:) async throws -> [Place]`, injected into `MapViewModel` alongside `APIClientProtocol`/`LocationServiceProtocol`. `PhotonLocationSearchProvider` implements it over `URLSession`, with pure, independently-testable `PhotonEndpoint` (URL building) and `PhotonGeocoderDecoder` (GeoJSON parsing) doing the real work — mirroring `Endpoints`/`GeocoderDecoder`'s existing split for the CycleStreets client. Because Photon returns a fully-resolved place (name + coordinates) per result, there's no MapKit-style two-phase suggestion/resolve step: `MapViewModel`/`MapView` keep working with `[Place]` directly, essentially unchanged from their pre-feature shape aside from which provider `search(query:)` calls.

**Tech Stack:** Swift, SwiftUI, `@Observable`/`@MainActor` ViewModels, Swift Testing (`import Testing`, `@Test`, `#expect`), `URLSession`, `CoreLocation` (`CLLocationCoordinate2D` for bias only — no MapKit dependency in this feature anymore).

## Global Constraints

- Build/test command: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation` — the `-skipMacroValidation` flag is required on every invocation (per `CLAUDE.md`), not just this one.
- Tests use **Swift Testing** (`import Testing`, `@Test func ...`, `#expect(...)`), never XCTest.
- **TDD**: write the failing test, confirm it fails for the right reason, implement minimally, confirm green — applies to all of Task 1 (`PhotonEndpoint`/`PhotonGeocoderDecoder`) and most of Task 2 (`MapViewModel`). `PhotonLocationSearchProvider`'s own `URLSession` hop (Task 1) and `MapView`/`RootView`'s DI-plumbing changes (Task 2) and all of Task 4 (`SettingsView`) are build-verify-only, per `docs/SPEC.md` → Test coverage's established convention — the same shape of gap already accepted for `APIClient`'s own untested-directly network call.
- New source files go under `CycleStreets Ride Planner/Search/` (app target) and `CycleStreets Ride PlannerTests/Search/` (test target) — both already exist as folders under the Xcode 16+ `PBXFileSystemSynchronizedRootGroup`-synced root from the superseded plan's Task 2, so new files placed there are auto-included in their target. Do not hand-edit `project.pbxproj`.
- `docs/SPEC.md` must be updated in the same commit as any change that materially changes a screen, ViewModel contract, API endpoint, or cross-cutting pattern (per `CLAUDE.md` / `docs/REVIEW_CHECKLIST.md`).
- Never touch `Resources/APIKey_dev.txt` / `Resources/ThunderforestAPIKey_dev.txt`'s `skip-worktree` flag; this feature needs no new secrets (Photon's public demo API requires no key).
- Design doc: `docs/superpowers/specs/2026-08-08-improve-typeahead-design.md` — consult it for rationale (why a single debounced call and not a stream, why the two-phase resolve design is gone, the `near`/bias-coordinate span decision, attribution placement).

## File Structure

- **Modify:** `CycleStreets Ride Planner/Search/LocationSearchProviding.swift` — replace with the single-method protocol; delete `SearchSuggestion`/`LocationSearchError` (Task 1).
- **Delete:** `CycleStreets Ride Planner/Search/MapKitLocationSearchProvider.swift` (Task 1).
- **Create:** `CycleStreets Ride Planner/Search/PhotonEndpoint.swift`, `CycleStreets Ride Planner/Search/PhotonGeocoderDecoder.swift`, `CycleStreets Ride Planner/Search/PhotonLocationSearchProvider.swift` (Task 1).
- **Create:** `CycleStreets Ride PlannerTests/Search/PhotonEndpointTests.swift`, `CycleStreets Ride PlannerTests/Search/PhotonGeocoderDecoderTests.swift` (Task 1).
- **Modify:** `CycleStreets Ride Planner/Models/Place.swift` — remove the MapKit-specific `init(mapItem:)` and its `import MapKit` (Task 1).
- **Delete:** `CycleStreets Ride PlannerTests/Models/PlaceTests.swift` — tested only the now-removed `init(mapItem:)` (Task 1).
- **Modify:** `CycleStreets Ride Planner/App/AppEnvironment.swift` — point `locationSearchProvider`'s default at `PhotonLocationSearchProvider()` (Task 1).
- **Create:** `CycleStreets Ride PlannerTests/Search/MockLocationSearchProvider.swift` — test double for the new single-method protocol (Task 2).
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapViewModel.swift` — restore debounced `search(query:)`/`searchTextChanged(_:)` pointed at the new provider, add bias-coordinate caching (Task 2).
- **Modify:** `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift` — restore/adapt the debounce test suite (Task 2).
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapView.swift` — init signature only, threading the new dependency through (Task 2).
- **Modify:** `CycleStreets Ride Planner/App/RootView.swift` — thread the environment value through to `MapView` (Task 2).
- **Modify:** `CycleStreets Ride Planner/Networking/APIClient.swift` — remove `geocode(query:)` from `APIClientProtocol`/`APIClient` (Task 3).
- **Modify:** `CycleStreets Ride Planner/Networking/Endpoints.swift` — remove `geocode(query:apiKey:)` (Task 3).
- **Delete:** `CycleStreets Ride Planner/Networking/GeocoderDecoder.swift`, `CycleStreets Ride PlannerTests/Networking/GeocoderDecoderTests.swift` (Task 3).
- **Modify:** `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift` — remove geocode-related fields/method (Task 3).
- **Modify:** `CycleStreets Ride PlannerTests/Networking/APIClientTests.swift` — remove `testGeocodeBuildsCorrectURL` (Task 3).
- **Modify:** `CycleStreets Ride Planner/Features/Settings/SettingsView.swift` — add OSM/Photon attribution links (Task 4).
- **Modify:** `docs/SPEC.md` — Task 1 (Search, Models, Test coverage sections), Task 2 (Map screen section), Task 3 (Networking, Test coverage sections), Task 4 (Settings, Known limitations sections).

---

### Task 1: Replace `LocationSearchProviding`'s MapKit shape with a Photon-backed single-call design

**Files:**
- Modify: `CycleStreets Ride Planner/Search/LocationSearchProviding.swift`
- Delete: `CycleStreets Ride Planner/Search/MapKitLocationSearchProvider.swift`
- Create: `CycleStreets Ride Planner/Search/PhotonEndpoint.swift`
- Create: `CycleStreets Ride Planner/Search/PhotonGeocoderDecoder.swift`
- Create: `CycleStreets Ride Planner/Search/PhotonLocationSearchProvider.swift`
- Create: `CycleStreets Ride PlannerTests/Search/PhotonEndpointTests.swift`
- Create: `CycleStreets Ride PlannerTests/Search/PhotonGeocoderDecoderTests.swift`
- Modify: `CycleStreets Ride Planner/Models/Place.swift`
- Delete: `CycleStreets Ride PlannerTests/Models/PlaceTests.swift`
- Modify: `CycleStreets Ride Planner/App/AppEnvironment.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Produces: `protocol LocationSearchProviding: Sendable { func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place] }`; `final class PhotonLocationSearchProvider: LocationSearchProviding`; `enum PhotonEndpoint { static func search(query: String, near coordinate: CLLocationCoordinate2D?) throws -> URL }`; `enum PhotonGeocoderDecoder { static func decode(_ data: Data) throws -> [Place] }` — all consumed by Task 2.

**Why this task isn't split further:** `AppEnvironment.swift`'s `LocationSearchProviderKey.defaultValue` must conform to whatever `LocationSearchProviding` currently requires. Changing the protocol's shape without also replacing `MapKitLocationSearchProvider` (which implements the *old* shape) in the same commit leaves the environment key's default value failing to conform — the project won't build. So the protocol rewrite, the deletion of the old provider, and the addition of the new one all have to land together, the same reasoning the (superseded) plan already used for its own Task 3.

- [ ] **Step 1: Write the failing tests for `PhotonEndpoint`**

Create `CycleStreets Ride PlannerTests/Search/PhotonEndpointTests.swift`:

```swift
//
//  PhotonEndpointTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import CoreLocation
@testable import CycleStreets_Ride_Planner

struct PhotonEndpointTests {

    @Test func searchBuildsCorrectURLWithoutBias() throws {
        let url = try PhotonEndpoint.search(query: "Cambridge", near: nil)
        #expect(url.host == "photon.komoot.io")
        #expect(url.path == "/api/")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["q"] == "Cambridge")
        #expect(items["limit"] == "6")
        #expect(items["lat"] == nil)
        #expect(items["lon"] == nil)
    }

    @Test func searchBuildsCorrectURLWithBias() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
        let url = try PhotonEndpoint.search(query: "Cambridge", near: coordinate)
        #expect(url.absoluteString.contains("lat=52.2053"))
        #expect(url.absoluteString.contains("lon=0.1218"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/PhotonEndpointTests"`
Expected: FAIL to build — `PhotonEndpoint` doesn't exist yet.

- [ ] **Step 3: Create `PhotonEndpoint.swift`**

Create `CycleStreets Ride Planner/Search/PhotonEndpoint.swift`:

```swift
//
//  PhotonEndpoint.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

/// Builds request URLs for Photon's public demo geocoder API
/// (https://photon.komoot.io) — see
/// docs/superpowers/specs/2026-08-08-improve-typeahead-design.md for why
/// this replaced Apple MapKit for search.
enum PhotonEndpoint {
    private static let base = "https://photon.komoot.io/api/"

    /// `near`, when provided, biases (doesn't filter) results toward that
    /// coordinate via Photon's `lat`/`lon` params.
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/PhotonEndpointTests"`
Expected: PASS (2 tests).

- [ ] **Step 5: Write the failing tests for `PhotonGeocoderDecoder`**

Create `CycleStreets Ride PlannerTests/Search/PhotonGeocoderDecoderTests.swift`:

```swift
//
//  PhotonGeocoderDecoderTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import Foundation
@testable import CycleStreets_Ride_Planner

struct PhotonGeocoderDecoderTests {

    @Test func decodesFeatureIntoPlaceWithFullAddress() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleWithFullAddress)
        #expect(places.count == 1)
        #expect(places[0].name == "Cambridge")
        #expect(places[0].near == "Cambridge, Cambridgeshire, England, United Kingdom")
        #expect(places[0].coordinate.longitude == 0.1186637)
        #expect(places[0].coordinate.latitude == 52.2055314)
    }

    @Test func fallsBackToStreetWhenNameMissing() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleMissingName)
        #expect(places[0].name == "Trumpington Street")
    }

    @Test func fallsBackToUnknownLocationWhenNameAndStreetMissing() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleMissingNameAndStreet)
        #expect(places[0].name == "Unknown location")
    }

    @Test func nearFallsBackToDistrictWhenCityMissing() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleCityLevelResult)
        #expect(places[0].near == "Cambridgeshire, England, United Kingdom")
    }

    @Test func handlesMissingAddressFieldsEntirely() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleNoAddressFields)
        #expect(places[0].near == nil)
    }

    @Test func skipsFeatureWithMalformedCoordinates() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleMalformedCoordinates)
        #expect(places.isEmpty)
    }

    @Test func placesHaveDistinctIdentifiers() throws {
        let places = try PhotonGeocoderDecoder.decode(sampleTwoFeatures)
        #expect(places[0].id != places[1].id)
    }
}

private let sampleWithFullAddress = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "osm_type": "N",
                "osm_id": 20971094,
                "name": "Cambridge",
                "city": "Cambridge",
                "county": "Cambridgeshire",
                "state": "England",
                "country": "United Kingdom",
                "postcode": "CB2 3NR"
            },
            "geometry": { "type": "Point", "coordinates": [0.1186637, 52.2055314] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleMissingName = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "street": "Trumpington Street",
                "city": "Cambridge",
                "country": "United Kingdom"
            },
            "geometry": { "type": "Point", "coordinates": [0.1218, 52.2001] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleMissingNameAndStreet = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": { "country": "United Kingdom" },
            "geometry": { "type": "Point", "coordinates": [0.1, 52.2] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleCityLevelResult = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": {
                "name": "Cambridge",
                "district": "Cambridgeshire",
                "state": "England",
                "country": "United Kingdom"
            },
            "geometry": { "type": "Point", "coordinates": [0.1391537, 52.1975846] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleNoAddressFields = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": { "name": "Null Island" },
            "geometry": { "type": "Point", "coordinates": [0.0, 0.0] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleMalformedCoordinates = """
{
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "properties": { "name": "Bad Coordinates" },
            "geometry": { "type": "Point", "coordinates": [0.0] }
        }
    ]
}
""".data(using: .utf8)!

private let sampleTwoFeatures = """
{
    "type": "FeatureCollection",
    "features": [
        { "type": "Feature", "properties": { "name": "A" }, "geometry": { "type": "Point", "coordinates": [0.0, 1.0] } },
        { "type": "Feature", "properties": { "name": "B" }, "geometry": { "type": "Point", "coordinates": [2.0, 3.0] } }
    ]
}
""".data(using: .utf8)!
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/PhotonGeocoderDecoderTests"`
Expected: FAIL to build — `PhotonGeocoderDecoder` doesn't exist yet.

- [ ] **Step 7: Create `PhotonGeocoderDecoder.swift`**

Create `CycleStreets Ride Planner/Search/PhotonGeocoderDecoder.swift`:

```swift
//
//  PhotonGeocoderDecoder.swift
//  CycleStreets Ride Planner
//

import Foundation

/// Decodes Photon's GeoJSON `FeatureCollection` response
/// (https://photon.komoot.io) into `Place` values. Unlike CycleStreets'
/// geocoder, the API returns no stable per-result identifier, so each
/// `Place.id` is synthesized — same as `GeocoderDecoder` did.
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

- [ ] **Step 8: Run tests to verify they pass**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/PhotonGeocoderDecoderTests"`
Expected: PASS (7 tests).

- [ ] **Step 9: Replace `LocationSearchProviding.swift`'s contents**

Replace the entire contents of `CycleStreets Ride Planner/Search/LocationSearchProviding.swift` with:

```swift
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
```

- [ ] **Step 10: Create `PhotonLocationSearchProvider.swift`**

Create `CycleStreets Ride Planner/Search/PhotonLocationSearchProvider.swift`:

```swift
//
//  PhotonLocationSearchProvider.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation

/// Real `LocationSearchProviding` implementation backed by Photon's public
/// demo API (https://photon.komoot.io). The actual network hop here isn't
/// unit-tested directly — same accepted gap as `APIClient`'s own
/// `session.data(from:)` calls; `PhotonEndpoint`/`PhotonGeocoderDecoder`
/// carry the real test coverage.
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

- [ ] **Step 11: Delete `MapKitLocationSearchProvider.swift`**

```bash
git rm "CycleStreets Ride Planner/Search/MapKitLocationSearchProvider.swift"
```

- [ ] **Step 12: Remove `Place(mapItem:)` and delete `PlaceTests.swift`**

In `CycleStreets Ride Planner/Models/Place.swift`, remove the `import MapKit` line and the entire trailing extension:

```swift
extension Place {
    /// Builds a `Place` from a resolved MapKit search result. `mapItem.name`
    /// is usually present for real search results; the fallback only
    /// matters for hand-constructed test fixtures or unusual map items.
    init(mapItem: MKMapItem) {
        id = UUID().uuidString
        let itemName = mapItem.name
        name = (itemName?.isEmpty ?? true) ? "Unknown location" : itemName!
        let nearParts = [mapItem.placemark.locality, mapItem.placemark.administrativeArea].compactMap { $0 }
        near = nearParts.isEmpty ? nil : nearParts.joined(separator: ", ")
        coordinate = Coordinate(
            longitude: mapItem.placemark.coordinate.longitude,
            latitude: mapItem.placemark.coordinate.latitude
        )
    }
}
```

`Place.swift` should end up back to exactly its original shape: the `Place` struct itself, with `import Foundation` and `import CoreLocation` only (no `MapKit`).

```bash
git rm "CycleStreets Ride PlannerTests/Models/PlaceTests.swift"
```

- [ ] **Step 13: Update `AppEnvironment.swift`'s default**

In `CycleStreets Ride Planner/App/AppEnvironment.swift`, change:
```swift
private struct LocationSearchProviderKey: EnvironmentKey {
    static let defaultValue: any LocationSearchProviding = MapKitLocationSearchProvider()
}
```
to:
```swift
private struct LocationSearchProviderKey: EnvironmentKey {
    static let defaultValue: any LocationSearchProviding = PhotonLocationSearchProvider()
}
```

- [ ] **Step 14: Run the full test suite**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED, all tests pass — confirms nothing else in the app target still referenced `SearchSuggestion`, `LocationSearchError`, `MapKitLocationSearchProvider`, or `Place(mapItem:)` (nothing should, since Tasks 1–2 of the superseded plan never wired them into `MapViewModel`/`MapView`).

- [ ] **Step 15: Update `docs/SPEC.md`**

Replace the entire **Search** section with:
```markdown
## Search (`Search/LocationSearchProviding.swift`)

Live typeahead for the Map screen's From/To search, backed by
[Photon](https://photon.komoot.io) — a public, OSM-data-backed geocoder —
rather than CycleStreets' own geocoder (GitHub #19 — see
`docs/superpowers/specs/2026-08-08-improve-typeahead-design.md`: originally
scoped around Apple MapKit, revised once it became clear Apple's MapKit
terms restrict search-result usage to Apple's own map, conflicting with
this app's existing OSM-tile rendering).

`LocationSearchProviding` has a single member: `search(query:near:) async throws -> [Place]`.
Unlike `LocationServiceProtocol`, it isn't `@MainActor`-isolated — it's a
stateless, plain async HTTP call, matching `APIClientProtocol`'s own style.
The `near` parameter, when non-nil, biases (doesn't filter) results toward
that coordinate.

`PhotonLocationSearchProvider` is the real implementation:
`PhotonEndpoint.search(query:near:)` builds the request URL
(`GET https://photon.komoot.io/api/` with `q`, `limit=6`, and `lat`/`lon`
when biasing), `PhotonGeocoderDecoder.decode(_:)` parses the GeoJSON
`FeatureCollection` response into `[Place]` (`name` falls back to `street`
then a literal "Unknown location"; `near` is assembled from
`city`/`district`/`county`/`state`/`country`, skipping whichever Photon
omits for a given result). `EnvironmentValues.locationSearchProvider`
follows the identical DI pattern as `.apiClient`/`.locationService`
(`App/AppEnvironment.swift`), defaulting to a fresh
`PhotonLocationSearchProvider()`.
```

In the **Models** section, change:
```
`Place` (`displayName` combines `name`+`near`; `init(mapItem:)` builds one from a resolved MapKit search result — see "Search" below),
```
to:
```
`Place` (`displayName` combines `name`+`near`),
```

In the **Test coverage** section, change:
```
`Models/{JourneyTests, PlaceTests}`,
```
to:
```
`Models/{JourneyTests}`,
```
and change:
```
`Location/{MockLocationService}`.
```
to:
```
`Location/{MockLocationService}`, `Search/{PhotonEndpointTests, PhotonGeocoderDecoderTests}`.
```

In the **Test coverage** section's "Known gaps" sentence, change:
```
**Known gaps** (pure-SwiftUI-wiring or genuinely hard-to-unit-test, treated as build-verify-only per project convention): `SavedLocationsViewModel`, `SettingsView`, `GPXExportButton`, `ItineraryView`, `SavedRoutesView`, `Endpoints`, `MapStyleSheet`, `MapStyleThumbnail`, `LocationService` (the real `CLLocationManager` wrapper — not exercisable via `xcodebuild test` on a simulator without a simulated GPX location), `MapKitLocationSearchProvider` (same reasoning — a delegate-based wrapper around concrete `MKLocalSearchCompleter`/`MKLocalSearch` types with no public initializers usable in tests).
```
to:
```
**Known gaps** (pure-SwiftUI-wiring or genuinely hard-to-unit-test, treated as build-verify-only per project convention): `SavedLocationsViewModel`, `SettingsView`, `GPXExportButton`, `ItineraryView`, `SavedRoutesView`, `Endpoints`, `MapStyleSheet`, `MapStyleThumbnail`, `LocationService` (the real `CLLocationManager` wrapper — not exercisable via `xcodebuild test` on a simulator without a simulated GPX location).
```
(`PhotonLocationSearchProvider`'s own network hop is deliberately *not* added here — it's the same shape of untested-directly gap this codebase already accepts for `APIClient`, which also isn't listed.)

- [ ] **Step 16: Commit**

```bash
git add "CycleStreets Ride Planner/Search/LocationSearchProviding.swift" \
  "CycleStreets Ride Planner/Search/PhotonEndpoint.swift" \
  "CycleStreets Ride Planner/Search/PhotonGeocoderDecoder.swift" \
  "CycleStreets Ride Planner/Search/PhotonLocationSearchProvider.swift" \
  "CycleStreets Ride PlannerTests/Search/PhotonEndpointTests.swift" \
  "CycleStreets Ride PlannerTests/Search/PhotonGeocoderDecoderTests.swift" \
  "CycleStreets Ride Planner/Models/Place.swift" \
  "CycleStreets Ride Planner/App/AppEnvironment.swift" \
  docs/SPEC.md
git commit -m "$(cat <<'EOF'
feat: replace MapKit search provider with Photon (#19)

LocationSearchProviding simplifies to a single search(query:near:)
call now that the backing provider (Photon) returns fully-resolved
places per result, unlike MapKit's coordinate-less completions.
Removes MapKitLocationSearchProvider, SearchSuggestion, and
Place(mapItem:) — all obsolete. Not yet consumed by MapViewModel.
EOF
)"
```

---

### Task 2: Migrate `MapViewModel` + `MapView` to `LocationSearchProviding`

**Files:**
- Create: `CycleStreets Ride PlannerTests/Search/MockLocationSearchProvider.swift`
- Modify: `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`
- Modify: `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`
- Modify: `CycleStreets Ride Planner/Features/Map/MapView.swift`
- Modify: `CycleStreets Ride Planner/App/RootView.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Consumes: `LocationSearchProviding` (Task 1) — `func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place]`.
- Produces: `MapViewModel.init(apiClient:locationService:searchProvider:initialSelectedPlan:)`, `MapViewModel.biasCoordinate: CLLocationCoordinate2D?`, `MapView.init(apiClient:locationService:locationSearchProvider:pendingJourney:pendingPlaceSelection:)` — final signatures.

**Why this task isn't split further:** `MapViewModel.init` gains a new required parameter in this task, and `MapView.swift` is the only caller of that initializer — landing the ViewModel change alone would leave `MapView.swift` failing to compile. Same reasoning as the (superseded) plan's own Task 3.

#### Part A — `MapViewModel` (TDD)

- [ ] **Step 1: Create `MockLocationSearchProvider`**

Create `CycleStreets Ride PlannerTests/Search/MockLocationSearchProvider.swift`:

```swift
//
//  MockLocationSearchProvider.swift
//  CycleStreets Ride PlannerTests
//

import CoreLocation
@testable import CycleStreets_Ride_Planner

final class MockLocationSearchProvider: LocationSearchProviding {
    struct QueryCall {
        let query: String
        let near: CLLocationCoordinate2D?
    }

    private(set) var queriesReceived: [QueryCall] = []
    var resultsToReturn: [Place] = []
    var errorToThrow: Error?
    var delayMilliseconds: UInt64 = 0

    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place] {
        try Task.checkCancellation()
        if delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        try Task.checkCancellation()
        if let errorToThrow { throw errorToThrow }
        queriesReceived.append(QueryCall(query: query, near: coordinate))
        return resultsToReturn
    }
}
```

- [ ] **Step 2: Update `MapViewModelTests`'s setup**

In `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`, replace the class header:
```swift
@MainActor
final class MapViewModelTests {
    let client: MockAPIClient
    let locationService: MockLocationService
    let vm: MapViewModel

    init() {
        client = MockAPIClient()
        locationService = MockLocationService()
        vm = MapViewModel(apiClient: client, locationService: locationService)
    }
```
with:
```swift
@MainActor
final class MapViewModelTests {
    let client: MockAPIClient
    let locationService: MockLocationService
    let searchProvider: MockLocationSearchProvider
    let vm: MapViewModel

    init() {
        client = MockAPIClient()
        locationService = MockLocationService()
        searchProvider = MockLocationSearchProvider()
        vm = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
    }
```

Replace `testSearchUpdatesPlaces` (it used `client.placesToReturn`/`client.geocode`, which Task 3 will delete):
```swift
@Test func testSearchUpdatesPlaces() async throws {
    client.placesToReturn = [
        Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
              coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
    ]
    await vm.search(query: "Cambridge")
    #expect(vm.searchResults.count == 1)
    #expect(vm.searchResults[0].name == "Cambridge")
}
```
with:
```swift
@Test func testSearchUpdatesPlaces() async throws {
    searchProvider.resultsToReturn = [
        Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
              coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
    ]
    await vm.search(query: "Cambridge")
    #expect(vm.searchResults.count == 1)
    #expect(vm.searchResults[0].name == "Cambridge")
}
```

Replace `testSearchTextChangedDebouncesAndSearches`:
```swift
@Test func testSearchTextChangedDebouncesAndSearches() async throws {
    vm.searchDebounceMilliseconds = 100
    client.placesToReturn = [
        Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
              coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
    ]
    vm.searchTextChanged("Cambridge")
    try await waitUntil { vm.searchResults.count == 1 }
    #expect(vm.searchResults.count == 1)
    #expect(client.geocodeQueriesReceived == ["Cambridge"])
}
```
with:
```swift
@Test func testSearchTextChangedDebouncesAndSearches() async throws {
    vm.searchDebounceMilliseconds = 100
    searchProvider.resultsToReturn = [
        Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
              coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
    ]
    vm.searchTextChanged("Cambridge")
    try await waitUntil { vm.searchResults.count == 1 }
    #expect(vm.searchResults.count == 1)
    #expect(searchProvider.queriesReceived.map(\.query) == ["Cambridge"])
}
```

Replace `testSearchTextChangedCancelsPendingSearchOnRapidTyping`:
```swift
@Test func testSearchTextChangedCancelsPendingSearchOnRapidTyping() async throws {
    vm.searchDebounceMilliseconds = 150
    client.placesToReturn = [
        Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
    ]
    vm.searchTextChanged("Ca")
    try await Task.sleep(for: .milliseconds(50))
    vm.searchTextChanged("Cambridge")
    try await waitUntil { client.geocodeQueriesReceived == ["Cambridge"] }
    #expect(client.geocodeQueriesReceived == ["Cambridge"])
}
```
with:
```swift
@Test func testSearchTextChangedCancelsPendingSearchOnRapidTyping() async throws {
    vm.searchDebounceMilliseconds = 150
    searchProvider.resultsToReturn = [
        Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
    ]
    vm.searchTextChanged("Ca")
    try await Task.sleep(for: .milliseconds(50))
    vm.searchTextChanged("Cambridge")
    try await waitUntil { searchProvider.queriesReceived.map(\.query) == ["Cambridge"] }
    #expect(searchProvider.queriesReceived.map(\.query) == ["Cambridge"])
}
```

Replace `testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires`:
```swift
@Test func testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires() async throws {
    vm.searchDebounceMilliseconds = 10
    client.placesToReturn = [
        Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
    ]
    vm.searchTextChanged("Cambridge")
    try await waitUntil { vm.searchResults.count == 1 }
    #expect(vm.errorMessage == nil)
    #expect(vm.searchResults.count == 1)
}
```
with:
```swift
@Test func testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires() async throws {
    vm.searchDebounceMilliseconds = 10
    searchProvider.resultsToReturn = [
        Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
    ]
    vm.searchTextChanged("Cambridge")
    try await waitUntil { vm.searchResults.count == 1 }
    #expect(vm.errorMessage == nil)
    #expect(vm.searchResults.count == 1)
}
```

Replace `testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded`:
```swift
@Test func testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded() async throws {
    vm.searchDebounceMilliseconds = 10
    client.geocodeDelayMilliseconds = 100
    client.placesToReturn = [
        Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
    ]
    vm.searchTextChanged("Ca")
    try await Task.sleep(for: .milliseconds(30))
    vm.searchTextChanged("Cambridge")
    try await waitUntil { vm.searchResults.count == 1 }
    #expect(vm.errorMessage == nil)
    #expect(vm.searchResults.count == 1)
}
```
with:
```swift
@Test func testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded() async throws {
    vm.searchDebounceMilliseconds = 10
    searchProvider.delayMilliseconds = 100
    searchProvider.resultsToReturn = [
        Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
    ]
    vm.searchTextChanged("Ca")
    try await Task.sleep(for: .milliseconds(30))
    vm.searchTextChanged("Cambridge")
    try await waitUntil { vm.searchResults.count == 1 }
    #expect(vm.errorMessage == nil)
    #expect(vm.searchResults.count == 1)
}
```

Replace `testLoadJourneyClearsSearchResultsAndError`'s setup line (only the `client.placesToReturn`/`vm.searchResults` assignment changes, the rest of the test is unchanged):
```swift
client.placesToReturn = [
    Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
]
vm.searchResults = client.placesToReturn
```
with:
```swift
vm.searchResults = [
    Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
]
```

Replace `testInitSetsSelectedPlanFromInitialValue`:
```swift
@Test func testInitSetsSelectedPlanFromInitialValue() {
    let vm2 = MapViewModel(apiClient: client, locationService: locationService, initialSelectedPlan: .fastest)
    #expect(vm2.selectedPlan == .fastest)
}
```
with:
```swift
@Test func testInitSetsSelectedPlanFromInitialValue() {
    let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider, initialSelectedPlan: .fastest)
    #expect(vm2.selectedPlan == .fastest)
}
```

- [ ] **Step 3: Add new tests for bias-coordinate behavior**

Append to `MapViewModelTests` (before the closing `}`):

```swift
    @Test func testBiasCoordinateSetWhenLocationAuthorized() async throws {
        locationService.isAuthorized = true
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        try await waitUntil { vm2.biasCoordinate != nil }
        #expect(vm2.biasCoordinate?.latitude == 51.5)
        #expect(vm2.biasCoordinate?.longitude == -0.1)
    }

    @Test func testBiasCoordinateNotSetWhenLocationUnauthorized() async throws {
        locationService.isAuthorized = false
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm2.biasCoordinate == nil)
    }

    @Test func testSearchPassesBiasCoordinateToProvider() async throws {
        locationService.isAuthorized = true
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        try await waitUntil { vm2.biasCoordinate != nil }
        await vm2.search(query: "Cambridge")
        #expect(searchProvider.queriesReceived.last?.near?.latitude == 51.5)
        #expect(searchProvider.queriesReceived.last?.near?.longitude == -0.1)
    }

    @Test func testSearchPassesNilNearWhenNoBiasCoordinate() async throws {
        await vm.search(query: "Cambridge")
        #expect(searchProvider.queriesReceived.last?.near == nil)
    }
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/MapViewModelTests"`
Expected: FAIL to build — `MapViewModel` has no `init(apiClient:locationService:searchProvider:initialSelectedPlan:)` and no `biasCoordinate` property yet.

- [ ] **Step 5: Update `MapViewModel`**

In `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`:

Add a new property alongside `apiClient`/`locationService`:
```swift
private let apiClient: any APIClientProtocol
private let locationService: any LocationServiceProtocol
private var searchDebounceTask: Task<Void, Never>?
```
becomes:
```swift
private let apiClient: any APIClientProtocol
private let locationService: any LocationServiceProtocol
private let searchProvider: any LocationSearchProviding
private var searchDebounceTask: Task<Void, Never>?

/// Best-effort location bias for `search(query:)`, populated once at
/// `init` if location access is already authorized (never prompts).
/// Deliberately not `private` — tests poll it directly to know when the
/// background fetch has completed.
var biasCoordinate: CLLocationCoordinate2D?
```

Replace `init`:
```swift
init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, initialSelectedPlan: RoutePlan = .balanced) {
    self.apiClient = apiClient
    self.locationService = locationService
    self.selectedPlan = initialSelectedPlan
}
```
with:
```swift
init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, searchProvider: any LocationSearchProviding, initialSelectedPlan: RoutePlan = .balanced) {
    self.apiClient = apiClient
    self.locationService = locationService
    self.searchProvider = searchProvider
    self.selectedPlan = initialSelectedPlan

    // Best-effort, one-shot: bias search results toward the device's
    // location if it's already authorized. Never triggers the permission
    // prompt itself — opening search must not surprise the user with one.
    if locationService.isAuthorized {
        Task { [weak self] in
            guard let self else { return }
            guard let coordinate = try? await self.locationService.currentLocation() else { return }
            self.biasCoordinate = coordinate
        }
    }
}
```

Replace `search(query:)`:
```swift
func search(query: String) async {
    guard !query.isEmpty else { searchResults = []; return }
    do {
        searchResults = try await apiClient.geocode(query: query)
    } catch {
        // A newer keystroke may have cancelled this in-flight request via
        // searchTextChanged's debounce; that's not a user-facing error.
        guard !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
    }
}
```
with:
```swift
func search(query: String) async {
    guard !query.isEmpty else { searchResults = []; return }
    do {
        searchResults = try await searchProvider.search(query: query, near: biasCoordinate)
    } catch {
        // A newer keystroke may have cancelled this in-flight request via
        // searchTextChanged's debounce; that's not a user-facing error.
        guard !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
    }
}
```

`searchTextChanged(_:)` is unchanged — it already debounces and calls `search(query:)`, which now goes through `searchProvider` instead of `apiClient`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/MapViewModelTests"`
Expected: still FAIL to build at this point — `MapView.swift`/`RootView.swift` haven't been updated yet and still construct `MapViewModel`/`MapView` with the old signatures. Proceed to Part B before the suite can pass.

#### Part B — `MapView` + `RootView` (build-verify)

- [ ] **Step 7: Update `MapView`'s init**

In `CycleStreets Ride Planner/Features/Map/MapView.swift`, replace `init`:
```swift
init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
    let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
    let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
    _vm = State(initialValue: MapViewModel(apiClient: apiClient, locationService: locationService, initialSelectedPlan: initialPlan))
    _pendingJourney = pendingJourney
    _pendingPlaceSelection = pendingPlaceSelection
}
```
with:
```swift
init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, locationSearchProvider: any LocationSearchProviding, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
    let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
    let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
    _vm = State(initialValue: MapViewModel(apiClient: apiClient, locationService: locationService, searchProvider: locationSearchProvider, initialSelectedPlan: initialPlan))
    _pendingJourney = pendingJourney
    _pendingPlaceSelection = pendingPlaceSelection
}
```

No other changes to `MapView.swift` — `resultsList`, `selectPlace(_:)`, the bookmark button, and `.onSubmit` all already work with `[Place]` and don't need to change, since `searchResults`'s type never changed.

- [ ] **Step 8: Update `RootView`**

In `CycleStreets Ride Planner/App/RootView.swift`, add a new environment property:
```swift
@Environment(\.apiClient) private var apiClient
@Environment(\.locationService) private var locationService
```
becomes:
```swift
@Environment(\.apiClient) private var apiClient
@Environment(\.locationService) private var locationService
@Environment(\.locationSearchProvider) private var locationSearchProvider
```

Update the `MapView(...)` call:
```swift
MapView(apiClient: apiClient, locationService: locationService, pendingJourney: $pendingMapJourney, pendingPlaceSelection: $pendingPlaceSelection)
```
becomes:
```swift
MapView(apiClient: apiClient, locationService: locationService, locationSearchProvider: locationSearchProvider, pendingJourney: $pendingMapJourney, pendingPlaceSelection: $pendingPlaceSelection)
```

- [ ] **Step 9: Run the full test suite**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED, all tests pass — including every `MapViewModelTests` case from Part A and the full pre-existing suite.

If a test file wasn't recompiled and still reports stale results, per `CLAUDE.md`'s stale-incremental-build note: compare the `.xctest` bundle's mtime under `DerivedData/.../Products/Debug-iphonesimulator/*.app/PlugIns/*.xctest` against the changed source files' mtimes, and `touch` the source files if the bundle is newer.

- [ ] **Step 10: Manual simulator verification**

Build and run the app in the iOS Simulator (`iPhone 17`) and verify the golden path, per this project's convention for frontend changes:
1. Launch the app, land on the Map tab.
2. Tap the search field, type a real place name (e.g. "Cambridge"), wait briefly for the debounce. Confirm results appear.
3. Tap a result. Confirm the From field fills in, the picker advances to To, and the camera animates to roughly the right location.
4. Repeat for the To field; confirm a route auto-plans once both are set.
5. Search again, tap a result's bookmark icon. Confirm the "saved" confirmation appears and the location shows up under Saved Locations.
6. Confirm the "Current Location" pinned row still works unchanged.

- [ ] **Step 11: Update `docs/SPEC.md`**

In the **Map screen** section, change:
```
Search a start/end location (via CycleStreets geocoder, with debounced typeahead), plan a route, view it as a polyline + markers, clear it, or jump to the itinerary.
```
to:
```
Search a start/end location (via Photon, an OSM-data-backed geocoder, with debounced typeahead), plan a route, view it as a polyline + markers, clear it, or jump to the itinerary.
```

Change the `search(query:)` bullet:
```
  - `search(query:)` — immediate geocode; ignores cancellation errors (a superseded in-flight request from a stale keystroke is not a user-facing error — see `searchTextChanged`).
```
to:
```
  - `search(query:)` — immediate search via `LocationSearchProviding`, biased by `biasCoordinate` when set; ignores cancellation errors (a superseded in-flight request from a stale keystroke is not a user-facing error — see `searchTextChanged`).
  - `biasCoordinate: CLLocationCoordinate2D?` — best-effort, populated once at `init` if `locationService.isAuthorized` (never prompts); `nil` until that background fetch completes or if location access isn't already granted, in which case `search(query:)` proceeds unbiased.
```

- [ ] **Step 12: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapViewModel.swift" \
  "CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift" \
  "CycleStreets Ride PlannerTests/Search/MockLocationSearchProvider.swift" \
  "CycleStreets Ride Planner/Features/Map/MapView.swift" \
  "CycleStreets Ride Planner/App/RootView.swift" \
  docs/SPEC.md
git commit -m "$(cat <<'EOF'
feat: switch Map search to Photon-backed provider (#19)

MapViewModel.search(query:) now calls LocationSearchProviding instead
of the CycleStreets geocoder, biased by a best-effort location fix
cached at init. MapView/RootView changes are DI plumbing only —
[Place] never changed shape, so the UI layer is otherwise untouched.
Manually verified in the iOS Simulator.
EOF
)"
```

---

### Task 3: Remove the CycleStreets geocoder path

**Files:**
- Modify: `CycleStreets Ride Planner/Networking/APIClient.swift`
- Modify: `CycleStreets Ride Planner/Networking/Endpoints.swift`
- Delete: `CycleStreets Ride Planner/Networking/GeocoderDecoder.swift`
- Delete: `CycleStreets Ride PlannerTests/Networking/GeocoderDecoderTests.swift`
- Modify: `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`
- Modify: `CycleStreets Ride PlannerTests/Networking/APIClientTests.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Consumes: nothing new — by the end of Task 2, nothing in the app target calls `APIClientProtocol.geocode(query:)`, `Endpoints.geocode`, or `GeocoderDecoder` anymore.
- Produces: `APIClientProtocol` with exactly `planJourney(from:to:plan:)`, `downloadGPX(journeyID:plan:)`, `reloadJourney(itineraryID:plan:)`.

This task is deletion-only — no new behavior, so no TDD cycle. Verification is the full suite passing with the geocoder path gone and no dangling references.

- [ ] **Step 1: Remove `geocode` from `APIClientProtocol`/`APIClient`**

In `CycleStreets Ride Planner/Networking/APIClient.swift`, remove this line from the protocol:
```swift
    func geocode(query: String) async throws -> [Place]
```
and remove this method from `APIClient`:
```swift
    func geocode(query: String) async throws -> [Place] {
        let url = try Endpoints.geocode(query: query, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return try GeocoderDecoder.decode(data)
    }
```

- [ ] **Step 2: Remove `geocode` from `Endpoints`**

In `CycleStreets Ride Planner/Networking/Endpoints.swift`, remove:
```swift
    static func geocode(query: String, apiKey: String) throws -> URL {
        var c = URLComponents(string: "\(base)/geocoder")!
        c.queryItems = [
            .init(name: "key",     value: apiKey),
            .init(name: "q",       value: query),
            .init(name: "results", value: "6"),
            .init(name: "format",  value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }
```
The `private static let base = "https://api.cyclestreets.net/v2"` constant was only used by this method — remove it too.

- [ ] **Step 3: Delete `GeocoderDecoder.swift` and its tests**

```bash
git rm "CycleStreets Ride Planner/Networking/GeocoderDecoder.swift" \
  "CycleStreets Ride PlannerTests/Networking/GeocoderDecoderTests.swift"
```

- [ ] **Step 4: Remove geocode-related fields from `MockAPIClient`**

In `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`, remove these properties:
```swift
    var placesToReturn: [Place] = []
    var geocodeQueriesReceived: [String] = []
    var geocodeDelayMilliseconds: UInt64 = 0
```
and remove this method:
```swift
    func geocode(query: String) async throws -> [Place] {
        try Task.checkCancellation()
        if geocodeDelayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(geocodeDelayMilliseconds))
        }
        try Task.checkCancellation()
        try checkThrow()
        geocodeQueriesReceived.append(query)
        return placesToReturn
    }
```

- [ ] **Step 5: Remove the geocode URL test**

In `CycleStreets Ride PlannerTests/Networking/APIClientTests.swift`, remove:
```swift
    @Test func testGeocodeBuildsCorrectURL() throws {
        let url = try Endpoints.geocode(query: "Cambridge", apiKey: "k")
        #expect(url.absoluteString.contains("Cambridge"))
    }
```

- [ ] **Step 6: Run the full test suite**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED, all remaining tests pass.

- [ ] **Step 7: Update `docs/SPEC.md`**

In the **Networking — CycleStreets API contract** section, change:
```
`Networking/Endpoints.swift` builds URLs; `Networking/APIClient.swift` fetches + delegates decoding; `APIClientProtocol`: `planJourney(from:to:plan:)`, `geocode(query:)`, `downloadGPX(journeyID:plan:)`, `reloadJourney(itineraryID:plan:)`.
```
to:
```
`Networking/Endpoints.swift` builds URLs; `Networking/APIClient.swift` fetches + delegates decoding; `APIClientProtocol`: `planJourney(from:to:plan:)`, `downloadGPX(journeyID:plan:)`, `reloadJourney(itineraryID:plan:)`. (Geocoding/search moved to `LocationSearchProviding` — see "Search" above; it's no longer part of the CycleStreets API surface.)
```

Remove this bullet entirely:
```
- **Geocoding** is v2: `GET https://api.cyclestreets.net/v2/geocoder` with `key`, `q`, `results=6`, `format=json`. Response is a GeoJSON `FeatureCollection` — decoded by `GeocoderDecoder`, which synthesizes `Place.id` via `UUID()` since the API returns none.
```

In the **Test coverage** section, change:
```
`Networking/{APIKeyTests, APIClientTests, GeocoderDecoderTests, JourneyPlanDecoderTests, MockAPIClient}`,
```
to:
```
`Networking/{APIKeyTests, APIClientTests, JourneyPlanDecoderTests, MockAPIClient}`,
```

- [ ] **Step 8: Commit**

```bash
git add "CycleStreets Ride Planner/Networking/APIClient.swift" \
  "CycleStreets Ride Planner/Networking/Endpoints.swift" \
  "CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift" \
  "CycleStreets Ride PlannerTests/Networking/APIClientTests.swift" \
  docs/SPEC.md
git commit -m "$(cat <<'EOF'
refactor: remove the now-unused CycleStreets geocoder path (#19)

APIClientProtocol.geocode, Endpoints.geocode, and GeocoderDecoder are
dead code since MapViewModel switched to LocationSearchProviding in
the previous commit. Straight deletion, no dual-provider flag.
EOF
)"
```

---

### Task 4: OSM/Photon attribution in Settings

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Settings/SettingsView.swift`
- Modify: `docs/SPEC.md`

**Interfaces:** none — pure UI addition, nothing else depends on this task.

Build-verify-only: `SettingsView` is pure static SwiftUI content, already in SPEC.md's build-verify-only bucket.

- [ ] **Step 1: Add attribution links**

In `CycleStreets Ride Planner/Features/Settings/SettingsView.swift`, change:
```swift
            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersionString)
                Link("CycleStreets website", destination: URL(string: "https://www.cyclestreets.net")!)
                Link("GNU GPL License", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
```
to:
```swift
            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersionString)
                Link("CycleStreets website", destination: URL(string: "https://www.cyclestreets.net")!)
                Link("GNU GPL License", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                Link("OpenStreetMap data (search)", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                Link("Photon geocoder", destination: URL(string: "https://photon.komoot.io")!)
            }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual simulator verification**

Launch the app, go to Settings, confirm the "About" section shows both new links and that tapping "OpenStreetMap data (search)" and "Photon geocoder" opens the correct URLs (in-app Safari view or system browser, matching how "CycleStreets website"/"GNU GPL License" already behave).

- [ ] **Step 4: Update `docs/SPEC.md`**

In the **Settings** section, change:
```
### Settings (`Features/Settings/`)
`@AppStorage`-backed: `"defaultRoutePlan"` (default `.balanced`) — read by `MapView` at construction to seed `MapViewModel`'s initial `selectedPlan` (which of the 3 always-fetched route plans is pre-selected), not which plan is requested; `"useMetric"` (default `true`). Plus an About section (version, links). A third `@AppStorage` key, `"mapStyle"` (default `MapStyleOption.cyclOSM`), also persists across launches but isn't a Settings-screen toggle — it's read/written directly by `MapView`'s `layersButton`/`MapStyleSheet` picker (see Map screen section above).
```
to:
```
### Settings (`Features/Settings/`)
`@AppStorage`-backed: `"defaultRoutePlan"` (default `.balanced`) — read by `MapView` at construction to seed `MapViewModel`'s initial `selectedPlan` (which of the 3 always-fetched route plans is pre-selected), not which plan is requested; `"useMetric"` (default `true`). Plus an About section (version, links — including OpenStreetMap/Photon attribution for the Map screen's search, per GitHub #19). A third `@AppStorage` key, `"mapStyle"` (default `MapStyleOption.cyclOSM`), also persists across launches but isn't a Settings-screen toggle — it's read/written directly by `MapView`'s `layersButton`/`MapStyleSheet` picker (see Map screen section above).
```

In the **Known limitations / roadmap** section, change:
```
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names.
```
to:
```
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: editable saved-location names.
```

Then add a new closing paragraph after the existing "Map auto-centering..." paragraph:
```
Location search (GitHub #19) now uses [Photon](https://photon.komoot.io), a public OSM-data-backed geocoder, instead of CycleStreets' own geocoder — a straight replacement, not a flag-based dual-provider system. Originally scoped around Apple MapKit; revised mid-implementation once it became clear Apple's MapKit terms restrict search-result usage to Apple's own map, conflicting with this app's OSM-tile rendering (GitHub #9). Design record: `docs/superpowers/specs/2026-08-08-improve-typeahead-design.md`; implementation plan: `docs/superpowers/plans/2026-08-08-improve-typeahead.md`.
```

- [ ] **Step 5: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Settings/SettingsView.swift" docs/SPEC.md
git commit -m "$(cat <<'EOF'
feat: add OpenStreetMap/Photon attribution to Settings (#19)

Photon's search results are OSM-derived (ODbL); credited in the
About section per user preference, rather than inline near search.
EOF
)"
```

## Plan self-review notes

- **Spec coverage:** every design-doc decision has a task — the single debounced `search(query:near:)` call replacing the stream (Task 1's protocol + Task 2's restored debounce), no two-phase resolve (Task 2's unchanged `MapView`), bias-coordinate caching gated on non-prompting `isAuthorized` (Task 2's `init`), Photon's fallback-chain decoding (Task 1's `PhotonGeocoderDecoder` + its 7 tests), the straight-replacement/no-flag decision (Task 3's deletion), and Settings-section attribution (Task 4).
- **Task ordering double-checked:** Task 1 supersedes the two already-landed tasks without reverting them (per the design doc), verified buildable on its own since `MapViewModel`/`MapView` never consumed the old MapKit-shaped protocol. Task 2 keeps the ViewModel and View/RootView changes in one commit for the same "mutually load-bearing" reason as before. Task 3 is ordered after Task 2 specifically because Task 2 removes the app target's last caller of `apiClient.geocode(query:)`.
- **Type consistency:** `MapViewModel.init`'s parameter order (`apiClient, locationService, searchProvider, initialSelectedPlan`), `LocationSearchProviding.search(query:near:)`'s signature, and `MockLocationSearchProvider.QueryCall`'s shape are used identically across Task 1's protocol, Task 2's ViewModel code, test code, and View/RootView code.
