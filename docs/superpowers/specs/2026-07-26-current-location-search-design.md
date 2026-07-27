# Design: "Current Location" in the search dropdown

> Addresses GitHub issue #6 (route-planning half only — "use Current Location as
> the from/to point when planning a route"). The map-recentering half of that
> issue is a separate, smaller piece and is out of scope here.
>
> Open questions this resolves, originally raised in
> `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md` under
> "Current Location for journey planning": permission UX, from/to scope,
> display name, testability.

## Summary

Tapping into the Map screen's search field immediately shows a pinned
"Current Location" row in the results dropdown, above any typed-search
results — no separate button, no waiting for a query. Tapping it requests
the device's one-shot location (prompting for permission in-context, the
first time), then feeds that coordinate through the exact same
`selectPlace(_:as:)` flow a normal search result uses, so it plans a route,
draws markers, etc. identically. The dropdown is structured so a future
"Favourites" row can sit alongside it with no rework.

This is net-new device-location integration — no `CLLocationManager` or
location-permission code exists anywhere in the app today (confirmed via
repo-wide grep).

## Components

### `LocationService` (new: `Location/LocationService.swift`)

Protocol-based, mirroring `APIClientProtocol`'s DI pattern:

```swift
protocol LocationServiceProtocol: Sendable {
    func currentLocation() async throws -> CLLocationCoordinate2D
}

enum LocationServiceError: Error {
    case permissionDenied   // .denied, or the in-context prompt was declined
    case restricted         // e.g. parental controls / MDM
    case unavailable(Error) // CLLocationManager produced no fix
}
```

`LocationService` wraps `CLLocationManager`'s delegate API behind
`withCheckedThrowingContinuation`, doing a single one-shot
`requestLocation()` call — no continuous tracking, since route planning only
needs one fix. If authorization is `.notDetermined`, it calls
`requestWhenInUseAuthorization()` itself and awaits the result before
deciding whether to proceed. This means the system permission prompt fires
the first time the user actually taps "Current Location," never on app
launch.

Exposed via `EnvironmentValues.locationService` (new `LocationServiceKey`),
mirroring `EnvironmentValues.apiClient` in `App/AppEnvironment.swift`.
`RootView` reads it from environment and passes it explicitly into
`MapView.init(locationService:...)`, the same way it already does for
`apiClient` — `MapView` builds `MapViewModel` with it.

Build setting: `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` added
(this project uses `GENERATE_INFOPLIST_FILE = YES`, no checked-in
`Info.plist`, so this is a build-setting addition, not a plist edit).

### `MapViewModel`

New state and method:

```swift
var isPresentingLocationPermissionAlert = false

func useCurrentLocation(as role: WaypointRole) async {
    isLoading = true
    do {
        let coordinate = try await locationService.currentLocation()
        let place = Place(id: UUID().uuidString, name: "Current Location", near: nil,
                           coordinate: Coordinate(longitude: coordinate.longitude, latitude: coordinate.latitude))
        await selectPlace(place, as: role)
    } catch LocationServiceError.permissionDenied, LocationServiceError.restricted {
        isLoading = false
        isPresentingLocationPermissionAlert = true
    } catch {
        isLoading = false
        errorMessage = "Couldn't get your current location. Please try again."
    }
}
```

- Reuses the existing `selectPlace(_:as:)` → `planRoute` path unchanged, so
  the "Current Location" waypoint flows through planning, the map camera,
  and the itinerary exactly like a searched place, with no special-casing
  downstream.
- `isLoading = true` is set at the start of `useCurrentLocation`, before the
  location fetch begins — `planRoute` (called via `selectPlace`) already
  manages `isLoading` for the planning phase, so this just extends the
  existing full-screen `ProgressView` overlay to cover the location-fetch
  phase too. No new loading UI.
- `name: "Current Location"` is a literal, hardcoded label — no reverse
  geocoding, no new provider dependency. This matches the SPEC's existing
  "Known limitations" note.

### Never persisted as a `SavedLocation`

The bookmark ("save as Saved Location") affordance in `MapView.resultsList`
only exists on rows of `vm.searchResults`, operating on real geocoder
results. **The "Current Location" row must never be added to
`vm.searchResults`** — it stays a separate, distinct element pinned above
the results list, with no bookmark icon. This is a deliberate constraint,
not an incidental gap: it's the only path in the app that could persist a
`Place.name`, and "Current Location" frozen at a past coordinate under a
literal "Current Location" name would be actively misleading later. (Traced
end-to-end: map markers use hardcoded "Start"/"End" titles, the Save-route
name field starts blank with no place-derived default, `SavedRoute` doesn't
store place names at all, and GPX export is keyed by `journeyID` only — none
of those surfaces are at risk. The bookmark icon scoped to `searchResults`
is the one surface that would be, if this constraint weren't upheld.)

## UI (`MapView`)

- `resultsList`'s visibility condition changes from `!vm.searchResults.isEmpty`
  to `isSearchFieldFocused`, so the dropdown card appears the instant the
  field is tapped, before any typing.
- Inside that same card, a "Current Location" row (location-arrow SF Symbol +
  label) is pinned above `List(vm.searchResults)`, always visible while
  focused. Tapping it calls `vm.useCurrentLocation(as: selectingFor)` — so it
  respects the existing From/To segmented picker exactly like a normal
  result tap — then clears search text and drops focus once both waypoints
  are set, matching `selectPlace`'s existing behavior.
- No bookmark icon on this row (see above).

## Permission-denied / restricted UX

A dedicated alert, distinct from the existing generic `errorMessage` alert
(which only has a single "OK" button): "Location Access Needed", with
**Cancel** and **Open Settings** (`UIApplication.openSettingsURLString`)
buttons, driven by `MapViewModel.isPresentingLocationPermissionAlert`. Other
failures (GPS unavailable, a one-off `CLError`) fall back to the existing
generic `errorMessage` alert with a message like "Couldn't get your current
location. Please try again."

## Testing

- `MapViewModel.useCurrentLocation` is unit-testable via a
  `MockLocationService: LocationServiceProtocol` (same pattern as the
  existing `MockAPIClient`) — cases: success, `.permissionDenied`,
  `.restricted`, generic failure. Assert on `fromPlace`/`toPlace`,
  `routeOptions`, `isPresentingLocationPermissionAlert`, and `errorMessage`
  as appropriate.
- The real `LocationService` (`CLLocationManager` wrapper) and the new
  dropdown row in `MapView` are build-verify-only — joining the existing
  list of pure-SwiftUI-wiring/hard-to-unit-test items in the SPEC's Test
  coverage section. `CLLocationManager` isn't exercisable via
  `xcodebuild test` on a simulator without a simulated GPX location, which
  is out of scope for this feature's automated tests.

## Out of scope

- Map camera recentering to current location (the other half of issue #6) —
  separate, smaller piece of work.
- Reverse geocoding a human-readable address for "Current Location" —
  explicitly deferred per the roadmap note; the row shows the literal label
  only.
- A "save this waypoint" affordance directly on `fromPlace`/`toPlace` (would
  reopen the stale-name risk above — not requested, not building it).
- Favourites in the dropdown — mentioned as a future direction; this design
  only ensures the row structure doesn't preclude it.
