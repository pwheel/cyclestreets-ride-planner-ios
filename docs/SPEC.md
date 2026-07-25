# SPEC — CycleStreets Ride Planner (iOS)

> Living document. Describes what's actually built, not what was originally planned.
> **Must be updated in the same PR/commit as any change that adds, removes, or materially changes a screen, ViewModel, API contract, persistence schema, or cross-cutting pattern.** See `docs/REVIEW_CHECKLIST.md`.
>
> Last verified against: `worktree-implement-plan` @ `566c294`.
> Historical record (original plan, UAT findings, roadmap decisions) lives in `docs/superpowers/plans/` — this file is the current-state snapshot, those are the "how we got here."

## Overview

SwiftUI iOS app for planning cycle routes using the CycleStreets API (journey planning, geocoding, GPX export) and saving routes/locations locally. No user accounts — the app uses a single bundled API key.

## Architecture

- SwiftUI + MVVM. `@Observable @MainActor final class ...ViewModel` per feature; views hold `@State private var vm: ...ViewModel`.
- Models are plain `Codable, Equatable` structs/enums (`Journey`, `Segment`, `Coordinate`, `Place`, `SavedRoute`, `SavedLocation`, `RoutePlan`).
- Dependency injection: a single `any APIClientProtocol` is exposed via `EnvironmentValues.apiClient` (`App/AppEnvironment.swift`), built once from the bundled API key. Views/ViewModels take it as an init parameter rather than reading `@Environment` deep in the tree, except at the point of construction.
- Xcode 16+ `PBXFileSystemSynchronizedRootGroup` — new source files placed under a synced folder are auto-included in the target. Don't hand-edit `project.pbxproj` to add files.
- Testing: **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest, for all unit tests.

## Screens & ViewModels

### Map (`Features/Map/`)
The home screen. Search a start/end location (via CycleStreets geocoder, with debounced typeahead), plan a route, view it as a polyline + markers, clear it, or jump to the itinerary.

- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `currentJourney`, `isLoading`, `errorMessage`, `routePlan`.
  - `search(query:)` — immediate geocode; ignores cancellation errors (a superseded in-flight request from a stale keystroke is not a user-facing error — see `searchTextChanged`).
  - `searchTextChanged(_:)` — debounced (default 300ms, `searchDebounceMilliseconds` is injectable for tests) typeahead; cancels the prior pending search on each new keystroke.
  - `planRoute(from:to:)`, `clearRoute()`.
  - `loadJourney(_:)` — populates the map from a journey obtained outside the normal search flow (a reloaded saved route); synthesizes placeholder from/to `Place`s from the journey's own first/last coordinate since no searched `Place` exists for it.
  - `selectPlace(_:as:)` — assigns a `Place` to `.from`/`.to` (`WaypointRole`); once both are set, calls `planRoute`. Used both by tapping a search result and by the Saved Locations cross-tab hand-off.
- `MapView`: search bar with From/To segmented picker, results list (tap to select, bookmark icon to save as a Saved Location), map with polyline + Start/End markers, "Clear" button (also resets the From/To picker to "From"), toolbar link to `ItineraryView` once a route exists. Tapping the map (not the search UI) dismisses the keyboard.
- `RoutePolyline`: `MKPolyline` subclass, `.from(journey:)` factory.

### Itinerary (`Features/Itinerary/`)
Turn-by-turn view of a planned `Journey`. `ItineraryViewModel` (plain, not `@Observable`) formats segments into rows (street name, turn instruction, distance, duration) plus totals, respecting the `useMetric` setting. Toolbar: "Save" (names and persists via `SavedRoutesViewModel`) and `GPXExportButton`.

### Saved Routes (`Features/SavedRoutes/`)
`SavedRoutesViewModel`: `load()`, `save(journey:name:)`, `delete(at:)`, `reload(route:) async` (re-fetches the journey by itinerary ID via `apiClient.reloadJourney`, sets `loadedJourney`/`isLoading`/`errorMessage`). `SavedRoutesView` lists saved routes; tapping reloads and (via `onJourneyLoaded` callback) hands the journey to the Map tab rather than navigating within its own stack.

### Saved Locations (`Features/SavedLocations/`)
`SavedLocationsViewModel`: `load()`, `save(name:coordinate:)`, `delete(at:)`. No networking dependency. `SavedLocationsView` rows are tappable; a confirmation dialog picks From/To, then hands the `Place` + role to the Map tab.

### Settings (`Features/Settings/`)
`@AppStorage`-backed: `"defaultRoutePlan"` (default `.balanced`), `"useMetric"` (default `true`). Plus an About section (version, links).

### GPX Export (`Features/GPX/`)
`GPXExportButton(journeyID:plan:)` downloads via `apiClient.downloadGPX`, writes to a temp file, presents a `UIActivityViewController` share sheet.

## Cross-tab hand-off pattern

`SavedRoutesView`/`SavedLocationsView` live in the "Saved" tab; selecting an item needs to both populate `MapViewModel` (owned privately by `MapView`) and switch to the "Map" tab. Rather than hoisting `MapViewModel` to a shared owner, the pattern used is:

1. `RootView` owns `@State private var selectedTab: Tab` (bound to `TabView(selection:)`) plus pending-value state: `pendingMapJourney: Journey?`, `pendingPlaceSelection: PendingPlaceSelection?`.
2. Both are passed into `MapView` as `Binding`s.
3. `SavedRoutesView`/`SavedLocationsView` take an escaping callback (`onJourneyLoaded`, `onPlaceSelected`) rather than reaching into `RootView`'s state directly; `RootView` sets the pending value + `selectedTab = .map` inside the callback.
4. `MapView` observes the bindings via `.onChange(of:)`, applies them to its own `MapViewModel`, then clears the binding back to `nil`.

Reuse this pattern for any future "select something in tab A, act on it in tab B" flow rather than hoisting shared view model ownership.

## Networking — CycleStreets API contract (as verified live, not as originally planned)

`Networking/Endpoints.swift` builds URLs; `Networking/APIClient.swift` fetches + delegates decoding; `APIClientProtocol`: `planJourney(from:to:plan:)`, `geocode(query:)`, `downloadGPX(journeyID:plan:)`, `reloadJourney(itineraryID:plan:)`.

- **Journey planning** is v1, not v2: `GET https://www.cyclestreets.net/api/journey.json` with `key`, `plan`, `itinerarypoints=lon,lat|lon,lat`, `reporterrors=1`, `segments=1`. Response is the `marker`/`@attributes` shape with all-string-typed fields and space-separated coordinate strings — decoded by `JourneyPlanDecoder` (not `Codable` directly on `Journey`).
- **Reload** (re-fetch a previously-planned journey by ID, e.g. for a saved route) uses the same endpoint with `itinerary=<id>` instead of `itinerarypoints`.
- **Geocoding** is v2: `GET https://api.cyclestreets.net/v2/geocoder` with `key`, `q`, `results=6`, `format=json`. Response is a GeoJSON `FeatureCollection` — decoded by `GeocoderDecoder`, which synthesizes `Place.id` via `UUID()` since the API returns none.
- **GPX export** is *not* part of the JSON API — it's served from the public website URL namespace (`https://www.cyclestreets.net/journey/<id>/cyclestreets<id><plan>.gpx`), no API key required.
- No authenticated user session is needed for any of the above — verified live. There is no login/account feature (intentionally descoped — see `docs/superpowers/plans/2026-07-19-uat-findings-v1.md` Finding 2).

## Models

`RoutePlan` (`balanced`/`quietest`/`fastest`), `Coordinate`, `Segment`, `Journey` (`allCoordinates` flattens all segment points), `Place` (`displayName` combines `name`+`near`), `SavedRoute` (`id`, `journeyID`, `name` (var), `plan`, `distanceMetres`, `timeSeconds`, `savedAt`; `Journey.asSavedRoute(name:)` builds one), `SavedLocation` (`id`, `name` (var), `coordinate`).

## Persistence

`Persistence/RouteStore.swift` / `LocationStore.swift`: JSON-file-backed (not `UserDefaults`), `Documents/saved_routes.json` / `saved_locations.json`, atomic writes via `JSONEncoder`/`JSONDecoder`. Identical shape: `loadAll() throws -> [T]` (`[]` if file absent), `save(_:) throws` (upsert — removes any existing entry with the same `id`, then appends), `delete(id:) throws`.

## Secrets

`Networking/APIKey.swift` loads a key from a bundled `.txt` resource in `Resources/`: `APIKey_live.txt` (gitignored, real key, release builds — resolved when `CYCLESTREETS_ENV == "live"`) or `APIKey_dev.txt` (tracked in git but flagged `git update-index --skip-worktree` so a locally-set real key is never committed; contains a placeholder in the repo's actual history). `AppEnvironment` swallows a load failure to an empty-key client rather than crashing.

## Test coverage

`CycleStreets Ride PlannerTests/`: `Networking/{APIKeyTests, APIClientTests, GeocoderDecoderTests, JourneyPlanDecoderTests, MockAPIClient}`, `Features/{MapViewModelTests, ItineraryViewModelTests, SavedRoutesViewModelTests}`, `Models/JourneyTests`, `Persistence/{RouteStoreTests, LocationStoreTests}`.

**Known gaps** (pure-SwiftUI-wiring or genuinely hard-to-unit-test, treated as build-verify-only per project convention): `SavedLocationsViewModel`, `SettingsView`, `GPXExportButton`, `RoutePolyline`, `ItineraryView`, `SavedRoutesView`, `Endpoints`.

## Known limitations / roadmap

Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: simultaneous multi-route comparison (quietest/balanced/fastest shown together), switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names, "Current Location" via device location permissions.
