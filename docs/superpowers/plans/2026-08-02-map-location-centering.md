# Map Auto-Center + Recenter Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out GitHub issue #6's remaining half — auto-center the Map screen to the device's current location, and add a button above the map-style ("layers") button to recenter on demand.

**Architecture:** Both map rendering paths (Apple `Map`, `MapLibreSwiftUI.MapView`) already ship a built-in follow-user-location camera mode that draws a live "blue dot" and pans the camera entirely internally, stopping automatically on user gesture. `LocationServiceProtocol` gains one new non-prompting member, `isAuthorized: Bool`, used only to gate a passive one-time auto-center on the Map screen's first appearance so it never triggers the system permission prompt at launch. `MapViewModel.centerOnCurrentLocation()` mirrors the existing `useCurrentLocation(as:)` permission/error handling but never touches `fromPlace`/`toPlace`/routing — it's a pure camera action. `LocationService.currentLocation()` stays exactly the one-shot method it is today; no continuous tracking is added anywhere in this app's own code.

**Tech Stack:** SwiftUI (`MapKit`'s `Map`/`MapCameraPosition`/`UserAnnotation`), `MapLibreSwiftUI` (`MapViewCamera.trackUserLocation`), `@Observable` (Observation framework), Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- **Swift Testing, not XCTest**: `import Testing`, `@Test func ...`, `#expect(...)` (per `CLAUDE.md`).
- **TDD**: write the failing test, confirm it fails for the right reason, implement minimally, confirm green (per `CLAUDE.md`) — applies to Task 2 (`MapViewModel`). Task 1 (`LocationService`, a thin `CLLocationManager` wrapper) and Task 3 (`MapView`, pure SwiftUI camera/gesture wiring) are build-verify-only per `docs/SPEC.md` → Test coverage's established convention — no unit test, but Task 3 additionally requires manual simulator verification since it's user-visible UI behavior.
- `docs/SPEC.md` must be updated in the same commit as any change that materially changes a screen or ViewModel contract (per `CLAUDE.md`).
- Build/test command: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`. **The `-skipMacroValidation` flag is required** on every invocation (per `CLAUDE.md`).
- **Stale incremental build gotcha:** if a changed test file's result looks unchanged, compare the `.xctest` bundle mtime against the source file mtime and `touch` the source file if the bundle is newer (per `CLAUDE.md`).
- **Framework-native tracking only.** Do not add continuous location updates (a `startUpdatingLocation()`-style stream) to `LocationService` — `MapCameraPosition.userLocation(fallback:)` + `UserAnnotation()` (Apple) and `MapViewCamera.trackUserLocation(zoom:)` (MapLibre) handle the live dot and following internally. `LocationService.currentLocation()` stays one-shot.
- **Camera-only, never routing.** `MapViewModel.centerOnCurrentLocation()` must never set `fromPlace`/`toPlace` or trigger `planRoute` — that's the existing, separate `useCurrentLocation(as:)` search-row flow, untouched by this feature.
- **No prompt at launch.** The passive auto-center in `MapView` must only fire when `vm.isLocationAuthorized` is already `true` — never call `vm.centerOnCurrentLocation()` (which can prompt) from the auto-center path.

---

## File Structure

- **Modify:** `CycleStreets Ride Planner/Location/LocationService.swift` — Task 1: adds `isAuthorized` to `LocationServiceProtocol` and `LocationService`.
- **Modify:** `CycleStreets Ride PlannerTests/Location/MockLocationService.swift` — Task 1: adds settable `isAuthorized`.
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapViewModel.swift` — Task 2: adds `isLocationAuthorized`, `centerOnCurrentLocation()`.
- **Modify:** `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift` — Task 2: adds tests for both.
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapView.swift` — Task 3: recenter button, tracking-start helper, passive auto-center, `UserAnnotation()`, stale doc-comment fix, bottom-trailing overlay layout refactor.
- **Modify:** `docs/SPEC.md` — Task 1 (Location section), Task 2 (`MapViewModel` bullet), Task 3 (`MapView` bullet + Known limitations + GitHub #6 closing paragraph).

---

### Task 1: `LocationServiceProtocol.isAuthorized`

**Files:**
- Modify: `CycleStreets Ride Planner/Location/LocationService.swift`
- Modify: `CycleStreets Ride PlannerTests/Location/MockLocationService.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Produces (used by Task 2): `LocationServiceProtocol.isAuthorized: Bool` — non-prompting read, `true` for `.authorizedWhenInUse`/`.authorizedAlways`, `false` otherwise. Never triggers the system permission prompt.

This task has no test of its own — `LocationService` is a thin `CLLocationManager` wrapper, build-verify-only per the Global Constraints above (same convention as `currentLocation()`, which also has no direct unit test — only its protocol's consumers are tested via `MockLocationService`).

- [ ] **Step 1: Add `isAuthorized` to `LocationServiceProtocol`**

In `CycleStreets Ride Planner/Location/LocationService.swift`, replace:

```swift
@MainActor
protocol LocationServiceProtocol: Sendable {
    /// Fetches a single one-shot fix for the device's current location,
    /// requesting "when in use" authorization first if not yet determined.
    /// Throws `LocationServiceError.alreadyInProgress` if a previous call
    /// hasn't resolved yet — callers must not assume serialization.
    func currentLocation() async throws -> CLLocationCoordinate2D
}
```

with:

```swift
@MainActor
protocol LocationServiceProtocol: Sendable {
    /// Fetches a single one-shot fix for the device's current location,
    /// requesting "when in use" authorization first if not yet determined.
    /// Throws `LocationServiceError.alreadyInProgress` if a previous call
    /// hasn't resolved yet — callers must not assume serialization.
    func currentLocation() async throws -> CLLocationCoordinate2D

    /// Non-prompting read of whether location access is already granted
    /// (`.authorizedWhenInUse` or `.authorizedAlways`). Never triggers the
    /// system permission prompt — used to gate features that must not
    /// surprise the user with a prompt outside an explicit user action.
    var isAuthorized: Bool { get }
}
```

- [ ] **Step 2: Implement `isAuthorized` in `LocationService`**

In the same file, replace:

```swift
    override init() {
        super.init()
        manager.delegate = self
    }
```

with:

```swift
    override init() {
        super.init()
        manager.delegate = self
    }

    /// Non-prompting read of `CLLocationManager`'s current authorization
    /// status — never triggers the system permission prompt.
    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }
```

- [ ] **Step 3: Add `isAuthorized` to `MockLocationService`**

In `CycleStreets Ride PlannerTests/Location/MockLocationService.swift`, replace:

```swift
final class MockLocationService: LocationServiceProtocol {
    var coordinateToReturn = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
    var errorToThrow: Error?

    func currentLocation() async throws -> CLLocationCoordinate2D {
```

with:

```swift
final class MockLocationService: LocationServiceProtocol {
    var coordinateToReturn = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
    var errorToThrow: Error?
    var isAuthorized = false

    func currentLocation() async throws -> CLLocationCoordinate2D {
```

- [ ] **Step 4: Build to confirm it compiles**

Run: `xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Update `docs/SPEC.md`**

Under `## Location (`Location/LocationService.swift`)`, replace:

```markdown
`LocationServiceProtocol` is `@MainActor` + `Sendable`, with the single member `currentLocation() async throws -> CLLocationCoordinate2D`. `LocationService` implements it over `CLLocationManager` (one-shot `requestLocation()`, no continuous tracking), and is the `EnvironmentValues.locationService` default. Four invariants matter if you touch it:
```

with:

```markdown
`LocationServiceProtocol` is `@MainActor` + `Sendable`, with two members: `currentLocation() async throws -> CLLocationCoordinate2D` (one-shot fetch) and `isAuthorized: Bool` (non-prompting read of `CLLocationManager.authorizationStatus`, used to gate features — like Map screen auto-centering — that must never trigger the system permission prompt outside an explicit user action). `LocationService` implements it over `CLLocationManager` (one-shot `requestLocation()`, no continuous tracking), and is the `EnvironmentValues.locationService` default. Four invariants matter if you touch it:
```

- [ ] **Step 6: Commit**

```bash
git add "CycleStreets Ride Planner/Location/LocationService.swift" \
  "CycleStreets Ride PlannerTests/Location/MockLocationService.swift" \
  docs/SPEC.md
git commit -m "$(cat <<'EOF'
feat: add non-prompting isAuthorized read to LocationServiceProtocol

Lets MapViewModel gate passive map auto-centering (added next commit)
without ever triggering the system permission prompt at launch.
EOF
)"
```

---

### Task 2: `MapViewModel.isLocationAuthorized` + `centerOnCurrentLocation()` (TDD)

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`
- Modify: `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Consumes: `LocationServiceProtocol.isAuthorized: Bool`, `.currentLocation() async throws -> CLLocationCoordinate2D`, `LocationServiceError` (`.permissionDenied`, `.restricted`, `.unavailable`, `.alreadyInProgress`) — all from Task 1.
- Produces (used by Task 3): `MapViewModel.isLocationAuthorized: Bool` (computed proxy). `MapViewModel.centerOnCurrentLocation() async -> Bool` — `true` on a successful fetch (never sets `fromPlace`/`toPlace`/`routeOptions`); `false` on any failure. `.permissionDenied`/`.restricted` sets `isPresentingLocationPermissionAlert`; other failures set `errorMessage`; `.alreadyInProgress` is silent and leaves `isLoading` alone.

- [ ] **Step 1: Write the failing tests**

In `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`, add these tests right after `testUseCurrentLocationAlreadyInProgressIsSilentAndLeavesLoadingAlone` (and before `testSearchTextChangedWithEmptyQueryClearsResultsImmediately`):

```swift
    @Test func testIsLocationAuthorizedReflectsLocationService() {
        locationService.isAuthorized = false
        #expect(!vm.isLocationAuthorized)
        locationService.isAuthorized = true
        #expect(vm.isLocationAuthorized)
    }

    @Test func testCenterOnCurrentLocationSucceedsWithoutTouchingWaypointsOrRoute() async {
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(succeeded)
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
        #expect(vm.routeOptions.isEmpty)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationPermissionDeniedPresentsAlert() async {
        locationService.errorToThrow = LocationServiceError.permissionDenied
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationRestrictedPresentsAlert() async {
        locationService.errorToThrow = LocationServiceError.restricted
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationUnavailableSetsErrorMessage() async {
        locationService.errorToThrow = LocationServiceError.unavailable
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationAlreadyInProgressIsSilentAndLeavesLoadingAlone() async {
        locationService.errorToThrow = LocationServiceError.alreadyInProgress
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(vm.isLoading)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/MapViewModelTests/testIsLocationAuthorizedReflectsLocationService()"`
Expected: build FAILS — `MapViewModel` has no member `isLocationAuthorized` or `centerOnCurrentLocation`.

- [ ] **Step 3: Implement `isLocationAuthorized` and `centerOnCurrentLocation()`**

In `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`, replace:

```swift
    /// The active route among `routeOptions` — feeds `ItineraryView`, Save, and GPX export.
    var currentJourney: Journey? { routeOptions.first { $0.plan == selectedPlan }?.journey }

    private let apiClient: any APIClientProtocol
    private let locationService: any LocationServiceProtocol
```

with:

```swift
    /// The active route among `routeOptions` — feeds `ItineraryView`, Save, and GPX export.
    var currentJourney: Journey? { routeOptions.first { $0.plan == selectedPlan }?.journey }

    /// Non-prompting read of whether location access is already granted —
    /// used by `MapView` to gate passive map auto-centering so it never
    /// triggers the system permission prompt at launch.
    var isLocationAuthorized: Bool { locationService.isAuthorized }

    private let apiClient: any APIClientProtocol
    private let locationService: any LocationServiceProtocol
```

Then, at the end of the class, replace the tail of `useCurrentLocation(as:)`:

```swift
        } catch {
            isLoading = false
            errorMessage = "Couldn't get your current location. Please try again."
            return nil
        }
    }
}
```

with:

```swift
        } catch {
            isLoading = false
            errorMessage = "Couldn't get your current location. Please try again."
            return nil
        }
    }

    /// Fetches the device's current location purely to recenter the map
    /// camera — unlike `useCurrentLocation(as:)`, this never touches
    /// `fromPlace`/`toPlace` or triggers route planning. The caller doesn't
    /// need the coordinate itself: on success it switches the map camera
    /// into the frameworks' own follow-user-location tracking mode rather
    /// than centering on a point held here. Same permission/error handling
    /// as `useCurrentLocation`: `.permissionDenied`/`.restricted` sets
    /// `isPresentingLocationPermissionAlert`; other failures set
    /// `errorMessage`; `.alreadyInProgress` is swallowed silently, leaving
    /// `isLoading` owned by the first call.
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/MapViewModelTests"`
Expected: ALL PASS — including every pre-existing test in the file.

If any test file's result looks stale, compare the `.xctest` bundle mtime under `DerivedData/.../Products/Debug-iphonesimulator/*.app/PlugIns/*.xctest` against the source file's mtime and `touch` the source file if the bundle is newer, then rerun.

- [ ] **Step 5: Update `docs/SPEC.md`**

Under `### Map (`Features/Map/`)`, replace the `MapViewModel` bullet's first line and `useCurrentLocation` sub-bullet:

```markdown
- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `routeOptions`, `selectedPlan`, `currentJourney`, `isLoading`, `errorMessage`, `isPresentingLocationPermissionAlert`.
  - `useCurrentLocation(as:) -> Place?` — fetches the device's current location via `LocationServiceProtocol` (requesting "when in use" authorization in-context on first use, not at launch) and assigns it to the given `WaypointRole` as a `Place` named literally `"Current Location"` (no reverse geocoding), reusing `selectPlace(_:as:)` so planning/markers/itinerary behave identically to a searched place. Returns the resolved `Place`, or `nil` on any failure — unlike `selectPlace(_:as:)` this operation can fail, so callers must branch on the return value rather than re-reading `fromPlace`/`toPlace` after the `await` (which can't distinguish a fresh assignment from a pre-existing value). `MapView` uses this to advance the From→To picker and recenter the camera **only on success**, so a permission failure doesn't silently retarget the user's retry. On `.permissionDenied`/`.restricted` sets `isPresentingLocationPermissionAlert` instead of `errorMessage`, so the UI can offer a direct link to Settings; `.alreadyInProgress` (a duplicate trigger while a fetch is in flight) is swallowed silently, leaving `isLoading` owned by the first call; other failures set `errorMessage`. This `Place` is deliberately never added to `searchResults`, so it can never be bookmarked into `SavedLocation` storage under a name that goes stale.
```

with:

```markdown
- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `routeOptions`, `selectedPlan`, `currentJourney`, `isLoading`, `errorMessage`, `isPresentingLocationPermissionAlert`, `isLocationAuthorized`.
  - `isLocationAuthorized: Bool` — non-prompting proxy for `LocationServiceProtocol.isAuthorized`. `MapView` reads this once on first appearance to decide whether it's safe to auto-center the map without ever triggering the system permission prompt at launch.
  - `useCurrentLocation(as:) -> Place?` — fetches the device's current location via `LocationServiceProtocol` (requesting "when in use" authorization in-context on first use, not at launch) and assigns it to the given `WaypointRole` as a `Place` named literally `"Current Location"` (no reverse geocoding), reusing `selectPlace(_:as:)` so planning/markers/itinerary behave identically to a searched place. Returns the resolved `Place`, or `nil` on any failure — unlike `selectPlace(_:as:)` this operation can fail, so callers must branch on the return value rather than re-reading `fromPlace`/`toPlace` after the `await` (which can't distinguish a fresh assignment from a pre-existing value). `MapView` uses this to advance the From→To picker and recenter the camera **only on success**, so a permission failure doesn't silently retarget the user's retry. On `.permissionDenied`/`.restricted` sets `isPresentingLocationPermissionAlert` instead of `errorMessage`, so the UI can offer a direct link to Settings; `.alreadyInProgress` (a duplicate trigger while a fetch is in flight) is swallowed silently, leaving `isLoading` owned by the first call; other failures set `errorMessage`. This `Place` is deliberately never added to `searchResults`, so it can never be bookmarked into `SavedLocation` storage under a name that goes stale.
  - `centerOnCurrentLocation() -> Bool` — fetches the device's current location purely to recenter the map camera; unlike `useCurrentLocation(as:)`, never touches `fromPlace`/`toPlace` or triggers route planning, and the caller doesn't need the coordinate itself since `MapView` switches the camera into the map frameworks' own follow-user-location tracking mode on success rather than centering on a held point. Same permission/error handling as `useCurrentLocation(as:)` (`isPresentingLocationPermissionAlert` / `errorMessage` / silent `.alreadyInProgress`), reusing the same alerts and `isLoading` overlay — no new UI state.
```

- [ ] **Step 6: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapViewModel.swift" \
  "CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift" \
  docs/SPEC.md
git commit -m "$(cat <<'EOF'
feat: add MapViewModel.isLocationAuthorized + centerOnCurrentLocation

Camera-only current-location fetch, distinct from useCurrentLocation:
never touches fromPlace/toPlace or route planning. Not yet reachable
from the UI -- MapView wiring is the next commit.
EOF
)"
```

---

### Task 3: `MapView` — auto-center, recenter button, live dot

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Map/MapView.swift`
- Modify: `docs/SPEC.md`

This task is pure SwiftUI camera/gesture wiring — per the Global Constraints above, build-verify-only, no unit test. It's also the task that makes this feature user-visible, so it ends with manual simulator verification, not just a green build.

**Interfaces:**
- Consumes: `MapViewModel.isLocationAuthorized: Bool` (Task 2), `MapViewModel.centerOnCurrentLocation() async -> Bool` (Task 2), `MapViewModel.isLoading: Bool` (existing), `MapView.updateCamera(to:)` / `MapView.initialRegion` (existing, unchanged).

- [ ] **Step 1: Add `hasAutoCenteredOnLaunch` state and the shared tracking-start helper**

In `CycleStreets Ride Planner/Features/Map/MapView.swift`, replace:

```swift
    @State private var position = MapCameraPosition.region(MapView.initialRegion)
    @State private var mapLibreCamera = MapView.mapViewCamera(for: MapView.initialRegion)
    @State private var isPresentingMapStyleSheet = false
    @AppStorage("mapStyle") private var mapStyleRawValue = MapStyleOption.defaultOption.rawValue
    @Environment(\.thunderforestAPIKey) private var thunderforestAPIKey
```

with:

```swift
    @State private var position = MapCameraPosition.region(MapView.initialRegion)
    @State private var mapLibreCamera = MapView.mapViewCamera(for: MapView.initialRegion)
    @State private var isPresentingMapStyleSheet = false
    @State private var hasAutoCenteredOnLaunch = false
    @AppStorage("mapStyle") private var mapStyleRawValue = MapStyleOption.defaultOption.rawValue
    @Environment(\.thunderforestAPIKey) private var thunderforestAPIKey
```

Then replace:

```swift
    private func updateCamera(to region: MKCoordinateRegion) {
        position = .region(region)
        mapLibreCamera = MapView.mapViewCamera(for: region)
    }
```

with:

```swift
    private func updateCamera(to region: MKCoordinateRegion) {
        position = .region(region)
        mapLibreCamera = MapView.mapViewCamera(for: region)
    }

    /// Switches the camera into each framework's own follow-user-location
    /// tracking mode — draws the live "blue dot" and pans the camera to it,
    /// entirely internally (see the design doc for why this app doesn't
    /// roll its own continuous location tracking). Both triggers (passive
    /// auto-center and the recenter button) call this only once permission
    /// is already known to be granted, so it never itself provokes the
    /// system permission prompt.
    private func startTrackingCurrentLocation() {
        position = .userLocation(fallback: .region(MapView.initialRegion))
        mapLibreCamera = .trackUserLocation(zoom: 15)
    }
```

- [ ] **Step 2: Add the passive auto-center `.onAppear`**

In the same file, in `body`, replace the tail of the modifier chain:

```swift
        .onChange(of: pendingPlaceSelection) { _, newValue in
            guard let selection = newValue else { return }
            if selection.role == .from { selectingFor = .to }
            withAnimation {
                updateCamera(to: MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            Task {
                await vm.selectPlace(selection.place, as: selection.role)
                if vm.fromPlace != nil && vm.toPlace != nil {
                    isSearchFieldFocused = false
                }
                pendingPlaceSelection = nil
            }
        }
    }
```

with:

```swift
        .onChange(of: pendingPlaceSelection) { _, newValue in
            guard let selection = newValue else { return }
            if selection.role == .from { selectingFor = .to }
            withAnimation {
                updateCamera(to: MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            Task {
                await vm.selectPlace(selection.place, as: selection.role)
                if vm.fromPlace != nil && vm.toPlace != nil {
                    isSearchFieldFocused = false
                }
                pendingPlaceSelection = nil
            }
        }
        .onAppear {
            // Passive auto-center: only fires once permission was already
            // granted in a previous session, so it never prompts at launch.
            // `hasAutoCenteredOnLaunch` means switching tabs away and back
            // won't re-snap the camera if the user has since panned away.
            guard !hasAutoCenteredOnLaunch, vm.isLocationAuthorized else { return }
            hasAutoCenteredOnLaunch = true
            startTrackingCurrentLocation()
        }
    }
```

- [ ] **Step 3: Add the recenter button, its container layout, and its action method**

In the same file, update the overlay call in `body` — replace:

```swift
        .overlay(alignment: .bottomTrailing) { layersButton }
```

with:

```swift
        .overlay(alignment: .bottomTrailing) { mapControlButtons }
```

Then replace the `layersButton` computed property:

```swift
    private var layersButton: some View {
        Button {
            isPresentingMapStyleSheet = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Map style")
        .padding()
        .sheet(isPresented: $isPresentingMapStyleSheet) {
            MapStyleSheet(selection: mapStyleBinding, thunderforestAPIKey: thunderforestAPIKey)
        }
    }
```

with:

```swift
    private var mapControlButtons: some View {
        VStack(spacing: 12) {
            recenterButton
            layersButton
        }
        .padding()
    }

    private var recenterButton: some View {
        Button {
            recenterOnCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Recenter on current location")
    }

    private var layersButton: some View {
        Button {
            isPresentingMapStyleSheet = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Map style")
        .sheet(isPresented: $isPresentingMapStyleSheet) {
            MapStyleSheet(selection: mapStyleBinding, thunderforestAPIKey: thunderforestAPIKey)
        }
    }

    /// Fetches the current location via `MapViewModel` first (so a
    /// permission failure surfaces through the existing "Location Access
    /// Needed" / generic error alerts) and only then switches the camera
    /// into tracking mode — never lets the map frameworks request their own
    /// authorization silently with no app-level fallback UI on denial.
    private func recenterOnCurrentLocation() {
        guard !vm.isLoading else { return }
        Task {
            guard await vm.centerOnCurrentLocation() else { return }
            startTrackingCurrentLocation()
        }
    }
```

Note the `.padding()` moved from `layersButton` itself onto the new `mapControlButtons` container — otherwise each button would carry its own edge padding, doubling the gap between them instead of the `VStack`'s `spacing: 12`.

- [ ] **Step 4: Add `UserAnnotation()` to the Apple map path**

In the same file, replace:

```swift
    private func appleMap(style: MapStyle) -> some View {
        Map(position: $position) {
            ForEach(nonSelectedRouteOptions) { option in
```

with:

```swift
    private func appleMap(style: MapStyle) -> some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(nonSelectedRouteOptions) { option in
```

`UserAnnotation()` is added unconditionally (not gated on "is tracking active") — it's an independent content item, not tied to `position`'s current mode, so it keeps rendering regardless of camera state once authorized. This is what makes the dot persist through a user pan (only the camera's follow behavior stops on a gesture, not the annotation). The MapLibre path needs no equivalent addition — `MapViewCoordinator.swift` shows the wrapper only ever sets `userTrackingMode`, and `.trackUserLocation()` turns the puck on as a side effect of the underlying `MLNMapView`.

- [ ] **Step 5: Fix the now-stale doc comment on `region(for camera:)`**

In the same file, replace:

```swift
    /// Best-effort inverse of `mapViewCamera(for:)`, extracting an `MKCoordinateRegion` from
    /// whatever `CameraState` MapLibre's camera binding currently holds after a user gesture.
    /// Handles the two states this feature realistically produces (`.centered`, from gesture
    /// pans/pinches once the map has moved; `.rect`, our own programmatic bounding-box writes).
    /// Any other state (user-location tracking, showcase) falls back to `nil`, leaving `position`
    /// unchanged — this app never puts the OSM map into those states.
```

with:

```swift
    /// Best-effort inverse of `mapViewCamera(for:)`, extracting an `MKCoordinateRegion` from
    /// whatever `CameraState` MapLibre's camera binding currently holds after a user gesture.
    /// Handles the two states this feature realistically produces (`.centered`, from gesture
    /// pans/pinches once the map has moved; `.rect`, our own programmatic bounding-box writes).
    /// Any other state (`.trackingUserLocation`, while the recenter feature has following
    /// active; `showcase`) falls back to `nil`, leaving `position` unchanged. That's fine for
    /// `.trackingUserLocation`: it doesn't carry a coordinate for us to sync anyway — MapLibre
    /// pans its own view internally as GPS fixes arrive without updating this binding's value —
    /// and a real user gesture already exits tracking mode (flipping the binding to `.centered`)
    /// before this is ever called with it.
```

- [ ] **Step 6: Build to confirm it compiles**

Run: `xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Manually verify in the simulator**

First, verify passive auto-center with location already authorized (the exact scenario this feature targets — "granted in a previous session"):

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
open -a Simulator
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "CycleStreets Ride Planner.app" -path "*Debug-iphonesimulator*" -print -quit)
xcrun simctl install booted "$APP_PATH"
xcrun simctl privacy booted grant location-always uk.slartibartfast.CycleStreets-Ride-Planner
xcrun simctl location booted set 52.4862,-0.6133
xcrun simctl launch booted uk.slartibartfast.CycleStreets-Ride-Planner
sleep 2
xcrun simctl io booted screenshot /tmp/map-recenter-auto-center.png
```

Read `/tmp/map-recenter-auto-center.png` and confirm the camera is centered near 52.4862,-0.6133 with a blue dot visible — this coordinate is deliberately far from the app's default `initialRegion` (~52.2053,0.1218) so a pass is unambiguous.

Then verify the remaining scenarios by hand in Simulator.app (these need real taps, which `simctl` can't script):

1. `xcrun simctl privacy booted revoke location uk.slartibartfast.CycleStreets-Ride-Planner`, then relaunch — confirm the map opens on the default region with **no** permission prompt and no dot (passive auto-center correctly stayed silent).
2. Tap the new button above the layers button (bottom-trailing) — confirm the system permission prompt appears; allow it — confirm the camera animates to the simulated location and the blue dot appears.
3. Drag/pan the map — confirm the dot **stays visible** and the camera **stops following** (doesn't snap back on its own).
4. Tap the recenter button again — confirm the camera returns to the dot.
5. Open the layers sheet (now directly below the new button) and switch to an OSM style (e.g. CyclOSM) — confirm the dot does *not* carry over (expected, per the design doc) and the new map renders at a reasonable last-known position.
6. Revoke permission again, tap the recenter button — confirm the existing "Location Access Needed" alert appears with a working "Open Settings" button.
7. Plan a route (search two waypoints) — confirm the polyline/markers stay visible and unaffected before and after using the recenter button.

- [ ] **Step 8: Update `docs/SPEC.md`**

Under `### Map (`Features/Map/`)`, replace the `MapView` bullet:

```markdown
- `MapView`: search bar with From/To segmented picker, a results dropdown shown as soon as the search field is focused (not just once results arrive) — a pinned "Current Location" row at the top (no bookmark icon, deliberately never added to `searchResults` — see `MapViewModel.useCurrentLocation`), then the search-results list below it once non-empty (tap to select, bookmark icon to save as a Saved Location). Map shows one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan, Start/End markers (green/red), "Clear" button, toolbar link to `ItineraryView` once a route exists. A bottom-right layers button opens `MapStyleSheet`, letting the user pick between 3 Apple styles and 3 OpenStreetMap-tile styles (persisted via `@AppStorage("mapStyle")`); route/marker rendering is duplicated between the Apple (`Map`/`MapPolyline`/`Marker`) and OSM (`MapLibreSwiftUI.MapView`/`ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer`) code paths since they're different underlying APIs. A dedicated "Location Access Needed" alert (Cancel / Open Settings via `UIApplication.openSettingsURLString`) covers denied/restricted location permission, distinct from the generic error alert. Tapping the map (not the search UI) dismisses the keyboard.
```

with:

```markdown
- `MapView`: search bar with From/To segmented picker, a results dropdown shown as soon as the search field is focused (not just once results arrive) — a pinned "Current Location" row at the top (no bookmark icon, deliberately never added to `searchResults` — see `MapViewModel.useCurrentLocation`), then the search-results list below it once non-empty (tap to select, bookmark icon to save as a Saved Location). Map shows one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan, Start/End markers (green/red), "Clear" button, toolbar link to `ItineraryView` once a route exists. A bottom-right layers button opens `MapStyleSheet`, letting the user pick between 3 Apple styles and 3 OpenStreetMap-tile styles (persisted via `@AppStorage("mapStyle")`); route/marker rendering is duplicated between the Apple (`Map`/`MapPolyline`/`Marker`) and OSM (`MapLibreSwiftUI.MapView`/`ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer`) code paths since they're different underlying APIs. Stacked directly above the layers button, a recenter button (`location.fill`) switches the camera into each framework's own follow-user-location tracking mode (`MapCameraPosition.userLocation(fallback:)` + `UserAnnotation()` for Apple, `MapViewCamera.trackUserLocation(zoom:)` for MapLibre) — a live "blue dot" that follows the device until the user pans, at which point the dot stays put while the camera stops following; switching map style while tracking drops it (rebuilds the underlying map view). The Map screen also auto-centers this way once, passively, the first time it appears after launch — only if location access was already granted in a previous session, so it never triggers the permission prompt at launch (see `MapViewModel.isLocationAuthorized`). A dedicated "Location Access Needed" alert (Cancel / Open Settings via `UIApplication.openSettingsURLString`) covers denied/restricted location permission for both the search row and the recenter button, distinct from the generic error alert. Tapping the map (not the search UI) dismisses the keyboard.
```

Under `## Known limitations / roadmap`, replace:

```markdown
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names. Zooming/centering the map to the device's current location (the other half of GitHub #6) is also not implemented — this feature only covers using Current Location as a route waypoint.
```

with:

```markdown
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names.
```

Then, at the end of the file, replace:

```markdown
"Current Location" as a route waypoint (GitHub #6, route-planning half) is implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-07-26-current-location-search-design.md`; implementation plan: `docs/superpowers/plans/2026-08-01-current-location-search.md`.
```

with:

```markdown
"Current Location" as a route waypoint (GitHub #6, route-planning half) is implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-07-26-current-location-search-design.md`; implementation plan: `docs/superpowers/plans/2026-08-01-current-location-search.md`.

Map auto-centering and a recenter button (GitHub #6, remaining half) are implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-08-02-map-location-centering-design.md`; implementation plan: `docs/superpowers/plans/2026-08-02-map-location-centering.md`.
```

- [ ] **Step 9: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapView.swift" docs/SPEC.md
git commit -m "$(cat <<'EOF'
feat: auto-center map + add recenter-on-current-location button

Closes out GitHub #6: the Map screen now auto-centers to the device's
location once per launch when already authorized, and a new button
above the layers button recenters on demand. Both switch the camera
into each map framework's own follow-user-location tracking mode
(live blue dot), rather than rolling continuous tracking ourselves.
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** every decision from the design doc has a task — the non-prompting `isAuthorized` read gating passive auto-center (Task 1), `centerOnCurrentLocation()` never touching routing state (Task 2), the shared `startTrackingCurrentLocation()` helper used by both triggers, the once-per-launch guard, the recenter button's placement/icon/reused alerts, `UserAnnotation()`'s unconditional placement (so the dot outlives a pan), the stale doc-comment fix, and the "drop tracking on style switch" decision (Task 3, verified manually in Step 7.5). SPEC.md is updated in the same commit as each contract change, per `CLAUDE.md`.
- **Type consistency:** `LocationServiceProtocol.isAuthorized: Bool` (Task 1 producer) is read identically as `locationService.isAuthorized` in Task 2's `MapViewModel.isLocationAuthorized`. `MapViewModel.centerOnCurrentLocation() async -> Bool` (Task 2 producer) is called identically as `await vm.centerOnCurrentLocation()` in Task 3's `recenterOnCurrentLocation()`. `MapView.startTrackingCurrentLocation()` is defined once in Task 3 Step 1 and called from both Task 3 Step 2 (`.onAppear`) and Step 3 (`recenterOnCurrentLocation()`).
- **No placeholders:** every step shows complete code, not descriptions of code.
