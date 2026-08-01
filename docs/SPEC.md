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
- Dependency injection: a single `any APIClientProtocol` is exposed via `EnvironmentValues.apiClient` (`App/AppEnvironment.swift`), built once from the bundled API key. `EnvironmentValues.locationService` (`any LocationServiceProtocol`, also in `AppEnvironment.swift`) follows the identical pattern. Views/ViewModels take these as init parameters rather than reading `@Environment` deep in the tree, except at the point of construction.
- Xcode 16+ `PBXFileSystemSynchronizedRootGroup` — new source files placed under a synced folder are auto-included in the target. Don't hand-edit `project.pbxproj` to add files.
- Testing: **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest, for all unit tests.
- Map rendering supports two providers, switched via `MapStyleOption` (`Features/Map/MapStyleOption.swift`): Apple's native styles (`MapStyle.standard/.hybrid/.imagery`) via SwiftUI's `Map`, and 3 OpenStreetMap-tile styles (OSM Standard/CyclOSM/Cycle Map) via `MapLibreSwiftUI.MapView` (the `maplibre/swiftui-dsl` SPM package, pinned `v0.25.0`) pointed at a small self-authored MapLibre raster-style JSON. `MapViewModel` is unaware of the distinction — it stays in `MapView.swift`.

## Screens & ViewModels

### Map (`Features/Map/`)
The home screen. Search a start/end location (via CycleStreets geocoder, with debounced typeahead), plan a route, view it as a polyline + markers, clear it, or jump to the itinerary.

- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `routeOptions`, `selectedPlan`, `currentJourney`, `isLoading`, `errorMessage`, `isPresentingLocationPermissionAlert`.
  - `useCurrentLocation(as:)` — fetches the device's current location via `LocationServiceProtocol` (requesting "when in use" authorization in-context on first use, not at launch) and assigns it to the given `WaypointRole` as a `Place` named literally `"Current Location"` (no reverse geocoding), reusing `selectPlace(_:as:)` so planning/markers/itinerary behave identically to a searched place. On `.permissionDenied`/`.restricted` sets `isPresentingLocationPermissionAlert` instead of `errorMessage`, so the UI can offer a direct link to Settings; other failures set `errorMessage`. This `Place` is deliberately never added to `searchResults`, so it can never be bookmarked into `SavedLocation` storage under a name that goes stale.
  - `routeOptions: [RouteOption]` — always 3 entries after a plan attempt (`.quietest, .balanced, .fastest` order), each holding that plan's `journey: Journey?`, `errorMessage: String?`, and computed `failed: Bool` (`journey == nil`) — the single source of truth for "this plan's request failed", used by `MapView`'s legend chip rather than re-deriving it from `journey`/`errorMessage` separately. `currentJourney` is computed from `routeOptions.first { $0.plan == selectedPlan }?.journey` — feeds `ItineraryView`, Save, and GPX export exactly as before.
  - `search(query:)` — immediate geocode; ignores cancellation errors (a superseded in-flight request from a stale keystroke is not a user-facing error — see `searchTextChanged`).
  - `searchTextChanged(_:)` — debounced (default 300ms, `searchDebounceMilliseconds` is injectable for tests) typeahead; cancels the prior pending search on each new keystroke.
  - `planRoute(from:to:)` — fetches all 3 `RoutePlan`s concurrently (`async let`, one `apiClient.planJourney` call per plan). Per-plan failures are captured in that plan's `RouteOption.errorMessage`, not the shared `errorMessage` (which remains reserved for `search(query:)` failures). If `selectedPlan`'s own request fails but another succeeds, `selectedPlan` auto-falls-back to the first successful plan in `.quietest, .balanced, .fastest` order.
  - `clearRoute()` — resets `routeOptions` to `[]` (plus from/to/search state, as before).
  - `loadJourney(_:)` — populates the map from a journey obtained outside the normal search flow (a reloaded saved route); sets `routeOptions` to a single entry for that journey's own plan (no comparison fetch of the other two plans — reloading a saved route is a distinct flow from fresh planning) and sets `selectedPlan` to match. Synthesizes placeholder from/to `Place`s from the journey's own first/last coordinate since no searched `Place` exists for it.
  - `selectPlace(_:as:)` — assigns a `Place` to `.from`/`.to` (`WaypointRole`); once both are set, calls `planRoute`. Used both by tapping a search result and by the Saved Locations cross-tab hand-off.
- `MapView`: search bar with From/To segmented picker, a results dropdown shown as soon as the search field is focused (not just once results arrive) — a pinned "Current Location" row at the top (no bookmark icon, deliberately never added to `searchResults` — see `MapViewModel.useCurrentLocation`), then the search-results list below it once non-empty (tap to select, bookmark icon to save as a Saved Location). Map shows one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan, Start/End markers (green/red), "Clear" button, toolbar link to `ItineraryView` once a route exists. A bottom-right layers button opens `MapStyleSheet`, letting the user pick between 3 Apple styles and 3 OpenStreetMap-tile styles (persisted via `@AppStorage("mapStyle")`); route/marker rendering is duplicated between the Apple (`Map`/`MapPolyline`/`Marker`) and OSM (`MapLibreSwiftUI.MapView`/`ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer`) code paths since they're different underlying APIs. A dedicated "Location Access Needed" alert (Cancel / Open Settings via `UIApplication.openSettingsURLString`) covers denied/restricted location permission, distinct from the generic error alert. Tapping the map (not the search UI) dismisses the keyboard.

### Itinerary (`Features/Itinerary/`)
Turn-by-turn view of a planned `Journey`. `ItineraryViewModel` (plain, not `@Observable`) formats segments into rows (street name, turn instruction, distance, duration) plus totals, respecting the `useMetric` setting. Toolbar: "Save" (names and persists via `SavedRoutesViewModel`) and `GPXExportButton`.

### Saved Routes (`Features/SavedRoutes/`)
`SavedRoutesViewModel`: `load()`, `save(journey:name:)`, `delete(at:)`, `reload(route:) async` (re-fetches the journey by itinerary ID via `apiClient.reloadJourney`, sets `loadedJourney`/`isLoading`/`errorMessage`). `SavedRoutesView` lists saved routes; tapping reloads and (via `onJourneyLoaded` callback) hands the journey to the Map tab rather than navigating within its own stack.

### Saved Locations (`Features/SavedLocations/`)
`SavedLocationsViewModel`: `load()`, `save(name:coordinate:)`, `delete(at:)`. No networking dependency. `SavedLocationsView` rows are tappable; a confirmation dialog picks From/To, then hands the `Place` + role to the Map tab.

### Settings (`Features/Settings/`)
`@AppStorage`-backed: `"defaultRoutePlan"` (default `.balanced`) — read by `MapView` at construction to seed `MapViewModel`'s initial `selectedPlan` (which of the 3 always-fetched route plans is pre-selected), not which plan is requested; `"useMetric"` (default `true`). Plus an About section (version, links). A third `@AppStorage` key, `"mapStyle"` (default `MapStyleOption.cyclOSM`), also persists across launches but isn't a Settings-screen toggle — it's read/written directly by `MapView`'s `layersButton`/`MapStyleSheet` picker (see Map screen section above).

### GPX Export (`Features/GPX/`)
`GPXExportButton(journeyID:plan:)` downloads via `apiClient.downloadGPX`, writes to a temp file, presents a `UIActivityViewController` share sheet.

## Cross-tab hand-off pattern

`SavedRoutesView`/`SavedLocationsView` live in the "Saved" tab; selecting an item needs to both populate `MapViewModel` (owned privately by `MapView`) and switch to the "Map" tab. Rather than hoisting `MapViewModel` to a shared owner, the pattern used is:

1. `RootView` owns `@State private var selectedTab: Tab` (bound to `TabView(selection:)`) plus pending-value state: `pendingMapJourney: Journey?`, `pendingPlaceSelection: PendingPlaceSelection?`.
2. Both are passed into `MapView` as `Binding`s.
3. `SavedRoutesView`/`SavedLocationsView` take an escaping callback (`onJourneyLoaded`, `onPlaceSelected`) rather than reaching into `RootView`'s state directly; `RootView` sets the pending value + `selectedTab = .map` inside the callback.
4. `MapView` observes the bindings via `.onChange(of:)`, applies them to its own `MapViewModel`, then clears the binding back to `nil`.

Reuse this pattern for any future "select something in tab A, act on it in tab B" flow rather than hoisting shared view model ownership.

## Location (`Location/LocationService.swift`)

`LocationServiceProtocol` is `@MainActor` + `Sendable`, with the single member `currentLocation() async throws -> CLLocationCoordinate2D`. `LocationService` implements it over `CLLocationManager` (one-shot `requestLocation()`, no continuous tracking), and is the `EnvironmentValues.locationService` default. Four invariants matter if you touch it:

- **Main-actor isolation.** The class is `@MainActor`, so `CLLocationManager` is created on main and therefore delivers its delegate callbacks on main. The three `CLLocationManagerDelegate` methods are declared `nonisolated` (the protocol requirements are non-isolated) and wrap their bodies in `MainActor.assumeIsolated { }`. Don't make them `async`/hop — the continuation state they read and nil out must be mutated from exactly one actor.
- **One fetch at a time.** `currentLocation()` guards on an `isFetchInFlight` flag and throws `LocationServiceError.alreadyInProgress` for a duplicate call, rather than overwriting (and thereby leaking) the pending `CheckedContinuation`. `MapView` also suppresses repeat taps while `vm.isLoading`; the service-level guard is the backstop.
- **Bounded authorization wait.** `locationManagerDidChangeAuthorization` deliberately ignores `.notDetermined` callbacks (the system emits them spuriously). Because there is a real state where `.notDetermined` is the *only* callback that will ever arrive — Location Services off device-wide with the app's own status still undetermined — the wait is raced against a 5s timeout task that resumes with `.notDetermined`, which `currentLocation()` maps to `.unavailable`. Keep both the guard and the ceiling.
- **Error mapping.** `.permissionDenied`/`.restricted` are the "link the user to Settings" cases (including `CLError.denied` from `didFailWithError`, which means Location Services are off system-wide despite an authorized app status). `.notDetermined` and `@unknown default` both map to `.unavailable` — a generic "try again", never a Settings link on a guess.

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

Thunderforest tile-provider key follows the identical pattern: `Resources/ThunderforestAPIKey_dev.txt` (tracked, `skip-worktree`, placeholder in history) / `Resources/ThunderforestAPIKey_live.txt` (gitignored). `APIKey.loadThunderforestKey()` shares its file-read/validate logic with `APIKey.load()` via a private `loadKey(named:)` helper.

## Test coverage

`CycleStreets Ride PlannerTests/`: `Networking/{APIKeyTests, APIClientTests, GeocoderDecoderTests, JourneyPlanDecoderTests, MockAPIClient}`, `Features/{MapViewModelTests, ItineraryViewModelTests, SavedRoutesViewModelTests, MapStyleOptionTests}`, `Models/JourneyTests`, `Persistence/{RouteStoreTests, LocationStoreTests}`, `Location/{MockLocationService}`.

**Known gaps** (pure-SwiftUI-wiring or genuinely hard-to-unit-test, treated as build-verify-only per project convention): `SavedLocationsViewModel`, `SettingsView`, `GPXExportButton`, `ItineraryView`, `SavedRoutesView`, `Endpoints`, `MapStyleSheet`, `MapStyleThumbnail`, `LocationService` (the real `CLLocationManager` wrapper — not exercisable via `xcodebuild test` on a simulator without a simulated GPX location).

## Known limitations / roadmap

Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names. Zooming/centering the map to the device's current location (the other half of GitHub #6) is also not implemented — this feature only covers using Current Location as a route waypoint.

Simultaneous multi-route comparison (quietest/balanced/fastest shown together) is implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-07-25-multi-route-comparison-design.md`; implementation plan: `docs/superpowers/plans/2026-07-25-multi-route-comparison.md`.

OSM tile-based map rendering (GitHub #9) is implemented — see the Map screen section above and Architecture. Design record: `docs/superpowers/specs/2026-07-26-map-tile-providers-design.md`.

"Current Location" as a route waypoint (GitHub #6, route-planning half) is implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-07-26-current-location-search-design.md`; implementation plan: `docs/superpowers/plans/2026-08-01-current-location-search.md`.
