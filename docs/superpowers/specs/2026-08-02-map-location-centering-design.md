# Design: Auto-center map + recenter button on current location

> Addresses the remainder of GitHub issue #6 — "automatically centre the map
> to the device's current location" and "add a location item to the map... to
> recentre on the device's current location." The route-planning half of that
> issue ("Current Location" as a search waypoint) is already implemented; see
> `docs/superpowers/specs/2026-07-26-current-location-search-design.md`.
> SPEC.md's "Known limitations" section currently calls this remainder out
> explicitly as not implemented.

## Summary

Two additions to the Map screen, both delivered via a live "blue dot" —
each map framework's own built-in follow-user-location camera mode, not a
custom continuous-tracking implementation:

1. **Passive auto-center**: the first time the Map screen appears after
   launch, if location access was already granted in a previous session, the
   camera silently centers on and starts following the device's location.
   If access hasn't been granted yet, nothing happens — no permission prompt
   fires at launch, preserving the existing "in-context, not at launch"
   principle documented for `LocationService`.
2. **Recenter button**: a new button stacked above the existing map-style
   ("layers") button. Tapping it fetches the current location (prompting for
   permission in-context on first use, same as the existing "Current
   Location" search row) and switches the camera into the same
   follow-user-location mode.

Both triggers converge on one shared camera action. Neither touches
`fromPlace`/`toPlace`/routing — this is purely a camera/map-chrome feature,
independent of the search-based "Current Location" waypoint flow.

## Why framework-native tracking, not our own continuous location updates

Both map rendering paths already ship a built-in "follow the user" camera
mode that draws the dot and moves the camera entirely internally, stopping
automatically the moment the user pans/gestures away (standard recenter-
button convention, matching Apple/Google Maps):

- Apple path: `MapCameraPosition.userLocation(fallback:)` + a `UserAnnotation()`
  in the `Map` content.
- MapLibre path: `MapViewCamera.trackUserLocation(zoom:pitch:)` — confirmed
  against the vendored `swiftui-dsl` package source (`Sources/MapLibreSwiftUI/Models/MapCamera/MapViewCamera.swift`,
  `CameraState.swift`); it's exactly what the package's own "User Location"
  example uses, backed by `MLNMapView`'s `userTrackingMode`.

Neither case's camera *state* carries a live coordinate — the frameworks pan
their own underlying map view internally as new fixes arrive, without our
`position`/`mapLibreCamera` bindings needing to round-trip per GPS update.
That means `LocationService` needs no continuous-tracking capability of its
own: `currentLocation()` stays exactly the one-shot method it is today. The
only new capability needed is a way to ask "is location already authorized?"
without prompting, to gate the passive auto-center.

Rolling our own continuous tracking (extending `LocationService` with
`startUpdatingLocation()`/a coordinate stream, rendering the dot as a custom
marker) was considered and rejected: it directly contradicts the "one fetch
at a time, no continuous tracking" invariant SPEC.md documents for
`LocationService` today, and reimplements dot rendering/animation/heading
the frameworks already provide for free.

## Components

### `LocationServiceProtocol` / `LocationService`

One new read-only member, alongside the existing `currentLocation()`:

```swift
protocol LocationServiceProtocol: Sendable {
    func currentLocation() async throws -> CLLocationCoordinate2D
    var isAuthorized: Bool { get }
}
```

`LocationService` backs this with `CLLocationManager`'s `authorizationStatus`
property (`true` for `.authorizedWhenInUse`/`.authorizedAlways`) — a plain
property read that never triggers the system permission prompt. This is the
only change to `LocationService`; `currentLocation()` is untouched.
`MockLocationService` (test double) gets a settable `isAuthorized` property,
defaulting to `false`.

### `MapViewModel`

Two additions, both reusing existing state/alerts rather than introducing
new ones:

```swift
/// Non-prompting read of whether location access is already granted — used
/// to gate passive auto-centering so it never prompts at launch.
var isLocationAuthorized: Bool { locationService.isAuthorized }

/// Fetches the device's current location purely to recenter the map camera
/// — unlike `useCurrentLocation(as:)`, this never touches `fromPlace`/
/// `toPlace` or triggers route planning. Returns whether the fetch
/// succeeded; the caller (MapView) doesn't need the coordinate itself,
/// since it switches the camera into a framework-driven tracking mode
/// rather than centering on a specific point we hold.
@discardableResult
func centerOnCurrentLocation() async -> Bool {
    isLoading = true
    do {
        _ = try await locationService.currentLocation()
        isLoading = false
        return true
    } catch LocationServiceError.alreadyInProgress {
        return false
    } catch LocationServiceError.permissionDenied, LocationServiceError.restricted {
        isLoading = false
        isPresentingLocationPermissionAlert = true
        return false
    } catch {
        isLoading = false
        errorMessage = "Couldn't get your current location. Please try again."
        return false
    }
}
```

Routing the recenter button through a real `currentLocation()` fetch first —
rather than just flipping the camera into tracking mode and letting the
frameworks request their own authorization — matters because the frameworks
have no app-level fallback UI: a permanently-denied user tapping the button
via framework-only tracking would just see nothing happen. Fetching first
means the button always gets this app's existing in-context prompt /
"Location Access Needed" alert (Cancel / Open Settings), consistent with the
search row. Once the fetch succeeds, permission is confirmed granted, so
switching to the frameworks' tracking mode afterward never re-prompts — it
just starts drawing the dot immediately.

### `MapView`

**Shared tracking-start helper**, called by both triggers:

```swift
private func startTrackingCurrentLocation() {
    position = .userLocation(fallback: .region(MapView.initialRegion))
    mapLibreCamera = .trackUserLocation()
}
```

**Passive auto-center** — a new `@State private var hasAutoCenteredOnLaunch = false`
guards a one-time check in `.onAppear`:

```swift
.onAppear {
    guard !hasAutoCenteredOnLaunch, vm.isLocationAuthorized else { return }
    hasAutoCenteredOnLaunch = true
    startTrackingCurrentLocation()
}
```

No `currentLocation()` fetch on this path — `isLocationAuthorized` already
confirms the frameworks can self-serve a fix without prompting. Guarding on
`hasAutoCenteredOnLaunch` means switching away from and back to the Map tab
mid-session won't re-snap the camera if the user has since panned elsewhere
— it only fires once per app launch.

**Recenter button** — a new `Button` in the same bottom-trailing overlay
stack as `layersButton`, stacked directly above it, matching its visual
treatment (`regularMaterial` circle, `.title2` icon):

```swift
private func recenterOnCurrentLocation() {
    guard !vm.isLoading else { return }
    Task {
        guard await vm.centerOnCurrentLocation() else { return }
        startTrackingCurrentLocation()
    }
}
```

Icon: `location.fill`. Accessibility label: "Recenter on current location".
Reuses the existing `vm.isLoading` full-screen `ProgressView` overlay and the
existing "Location Access Needed" / generic error alerts — no new loading or
error UI.

**The dot outlives the camera following it.** A user pan only cancels the
*camera's* follow behavior — the blue dot itself keeps showing at the
device's live position, and the recenter button remains available to snap
the camera back to it. Concretely: planning a route, tapping recenter, then
scrolling the map does **not** make the dot disappear; it just stops the
camera from continuing to chase the user's movement. Route polylines/markers
are a separate layer and are unaffected throughout.

This falls out of each framework's own model rather than anything we build:
- Apple path: `UserAnnotation()` is added unconditionally to `appleMap`'s
  content (not gated on "is tracking active") — it's an independent content
  item, not tied to `MapCameraPosition`'s current mode, so it keeps
  rendering regardless of camera state once authorized.
- MapLibre path: confirmed directly against `MapViewCoordinator.swift` — the
  wrapper only ever sets `mapView.userTrackingMode`, never touches
  `showsUserLocation`. Setting `userTrackingMode = .follow` (what
  `trackUserLocation()` does) turns the dot on as a side effect of the
  underlying `MLNMapView`/Mapbox-family SDK; setting it back to `.none` (what
  happens automatically on a user gesture) stops the *following* but leaves
  `showsUserLocation` — and so the dot — untouched.

Neither camera-state case carries a live coordinate, so there's no state for
us to fight once tracking starts — both frameworks natively drop out of
their own follow mode the moment the user gestures/pans, and the app's
existing gesture-sync handlers (`.onMapCameraChange` /
`.onChange(of: mapLibreCamera)`) pick up the resulting concrete region
exactly as they do today for any other manual pan. No new state or
gesture-handling code is needed for this.

**Switching map style while tracking**: not specially handled, and whether
the dot disappears depends on which style boundary is crossed —
**confirmed on-device**, not just reasoned from the camera-binding code
(an earlier draft of this design, before that confirmation, mis-predicted
an Apple→OSM/OSM→Apple asymmetry based on which direction the shared
`position`/`mapLibreCamera` bindings get overwritten; that turned out not
to be what determines persistence — remounting is):

- **Within the same rendering engine** (Apple↔Apple, or OSM↔OSM): the dot
  *does* persist, unlike a cross-engine switch — the same `Map` or
  `MapLibreSwiftUI.MapView` instance stays mounted (SwiftUI only updates
  its style/content, doesn't recreate the view), so the underlying
  `UIViewController`'s tracking state carries over untouched, same as a
  pan (see above).
- **Crossing between the two rendering engines** (Apple→OSM or OSM→Apple,
  either direction): the dot *does* disappear. Switching style via the
  layers sheet tears down and remounts an entirely new underlying map view
  (`Map` ↔ `MapLibreSwiftUI.MapView`), which always starts with no dot
  until tracking is engaged on it again — regardless of what the shared
  `position`/`mapLibreCamera` bindings still hold, since a freshly
  mounted view has no memory of the outgoing view's tracking state. The
  newly-mounted path's camera instead shows whatever `position`/
  `mapLibreCamera` last held as a static snapshot near (but not
  necessarily exactly) the live position. This matches how style
  switching already behaves outside of tracking (camera state is
  preserved best-effort across the two paths, not pixel-perfect).

Either way, this isn't specially handled — no explicit "currently
following" flag is introduced purely to special-case a fairly narrow
scenario. The user can tap recenter again after switching to resume
tracking (and the dot) on the new path.

## Error handling

- Permission denied/restricted (recenter button only — passive auto-center
  never reaches this since it's gated on already-granted access): existing
  "Location Access Needed" alert, Cancel / Open Settings.
- Other fetch failures (recenter button only): existing generic error alert,
  "Couldn't get your current location. Please try again."
- A second recenter tap while one is already in flight: guarded by
  `vm.isLoading`, matching the existing "Current Location" search row's
  repeat-tap guard.

## Testing

- `isLocationAuthorized` and `centerOnCurrentLocation()` are unit-tested via
  `MockLocationService`, mirroring the existing `useCurrentLocation` test
  coverage in `MapViewModelTests` — cases: authorized/not-authorized read,
  and fetch success / `.permissionDenied` / `.restricted` / generic failure
  for `centerOnCurrentLocation()`.
- The `MapView` wiring itself (button placement, `.onAppear` gating, camera-
  state assignment, `UserAnnotation()`) is build-verify-only, joining the
  existing list of pure-SwiftUI-wiring items in SPEC.md's Test coverage
  section — consistent with how the rest of `MapView`'s camera/gesture code
  is already treated.

## Out of scope

- Reverse geocoding, Favourites, and the "Current Location" search waypoint
  itself — all already covered by the existing search-row feature; untouched
  here.
- Heading/course-based tracking (`trackUserLocationWithHeading`/`WithCourse`)
  — not requested; plain `trackUserLocation()` only.
- Preserving live tracking across a map-style switch (see above) — accepted
  as a minor, narrow-scenario gap rather than added complexity.
- Any change to `useCurrentLocation(as:)` or the search-row flow — this
  feature is additive and doesn't touch that code path.
