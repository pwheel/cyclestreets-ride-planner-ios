# Current Location Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick "Current Location" as the from and/or to waypoint when planning a route, via a pinned row shown immediately in the Map screen's search dropdown.

**Architecture:** A new protocol-based `LocationServiceProtocol` (mirroring `APIClientProtocol`'s DI pattern) wraps `CLLocationManager`'s delegate API behind a one-shot `async throws -> CLLocationCoordinate2D` call, requesting "when in use" authorization in-context on first tap rather than at launch. `MapViewModel.useCurrentLocation(as:)` synthesizes a `Place` named literally "Current Location" from the fetched coordinate and feeds it through the existing `selectPlace(_:as:)` path unchanged, so planning/markers/itinerary all work identically to a searched place. The row lives outside `vm.searchResults` and carries no bookmark affordance, so it can never be persisted as a stale-named `SavedLocation`.

**Tech Stack:** SwiftUI, `@Observable` (Observation framework), `CoreLocation` (`CLLocationManager`), Swift Testing (`import Testing`, `@Test`, `#expect`), Swift structured concurrency (`withCheckedThrowingContinuation`).

## Global Constraints

- **Swift Testing, not XCTest**: `import Testing`, `@Test func ...`, `#expect(...)` (per `CLAUDE.md`).
- **TDD**: write the failing test, confirm it fails for the right reason, implement minimally, confirm green (per `CLAUDE.md`).
- Pure-SwiftUI-wiring changes (view layout, alert wiring, DI plumbing) are build-verify-only — no unit test required, per `docs/SPEC.md` → Test coverage convention. The real `LocationService` (`CLLocationManager` wrapper) is also build-verify-only — it isn't exercisable via `xcodebuild test` on a simulator without a simulated GPX location.
- `docs/SPEC.md` must be updated in the same commit as any change that materially changes a screen or ViewModel contract (per `CLAUDE.md`).
- Build/test command: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`. **The `-skipMacroValidation` flag is required** on every invocation now that `maplibre/swiftui-dsl` is a dependency (per `CLAUDE.md`).
- **Stale incremental build gotcha:** if a changed test file's result looks unchanged, compare the `.xctest` bundle mtime against the source file mtime and `touch` the source file if the bundle is newer (per `CLAUDE.md`).
- The "Current Location" row must never be added to `vm.searchResults` and must never gain a bookmark/save icon — that's the one surface in the app that persists a `Place.name`, and a `SavedLocation` frozen at a past coordinate under a literal "Current Location" name would be actively misleading later. See the design spec for the full trace of why every other surface (map markers, Save-route naming, GPX export) is already safe.

---

## File Structure

- **Create:** `CycleStreets Ride Planner/Location/LocationService.swift` — `LocationServiceProtocol`, `LocationServiceError`, and the real `CLLocationManager`-backed `LocationService`.
- **Create:** `CycleStreets Ride PlannerTests/Location/MockLocationService.swift` — test double conforming to `LocationServiceProtocol`.
- **Modify:** `CycleStreets Ride Planner/App/AppEnvironment.swift` — adds `EnvironmentValues.locationService`.
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapViewModel.swift` — adds `locationService` init param, `isPresentingLocationPermissionAlert`, `useCurrentLocation(as:)`.
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapView.swift` — Task 1: init param + pass-through only. Task 2: `resultsList` visibility change, pinned "Current Location" row, permission-denied alert.
- **Modify:** `CycleStreets Ride Planner/App/RootView.swift` — reads `\.locationService` from environment, passes it into `MapView.init`.
- **Modify:** `CycleStreets Ride Planner.xcodeproj/project.pbxproj` — adds `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` to the app target's Debug and Release build configs.
- **Modify:** `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift` — updates shared `init()` to pass a `MockLocationService`; adds `useCurrentLocation` tests.
- **Modify:** `docs/SPEC.md` — Architecture DI bullet + Map screen `MapViewModel` bullet + Test coverage (Task 1 commit); Map screen `MapView` bullet + "Known limitations / roadmap" line (Task 2 commit).

---

### Task 1: Location service + `MapViewModel.useCurrentLocation` (TDD)

**Files:**
- Create: `CycleStreets Ride Planner/Location/LocationService.swift`
- Create: `CycleStreets Ride PlannerTests/Location/MockLocationService.swift`
- Modify: `CycleStreets Ride Planner/App/AppEnvironment.swift`
- Modify: `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`
- Modify: `CycleStreets Ride Planner/Features/Map/MapView.swift`
- Modify: `CycleStreets Ride Planner/App/RootView.swift`
- Modify: `CycleStreets Ride Planner.xcodeproj/project.pbxproj`
- Modify: `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Produces (used by Task 2): `MapViewModel.useCurrentLocation(as role: WaypointRole) async` — on success, behaves exactly like `selectPlace(_:as:)` with a `Place(name: "Current Location", ...)`. On `.permissionDenied`/`.restricted`, sets `MapViewModel.isPresentingLocationPermissionAlert = true` and leaves `fromPlace`/`toPlace` untouched. On any other failure, sets `MapViewModel.errorMessage` and leaves `fromPlace`/`toPlace` untouched. `isLoading` is `true` for the location-fetch phase and always ends `false` on every exit path — including the success path where only one waypoint ends up set and `planRoute` never runs, so the spinner can never get stuck on.
- Consumes: `LocationServiceProtocol.currentLocation() async throws -> CLLocationCoordinate2D`, `LocationServiceError` (`.permissionDenied`, `.restricted`, `.unavailable`).

- [ ] **Step 1: Create the location service protocol + error type**

Create `CycleStreets Ride Planner/Location/LocationService.swift`:

```swift
//
//  LocationService.swift
//  CycleStreets Ride Planner
//

import CoreLocation

protocol LocationServiceProtocol {
    /// Fetches a single one-shot fix for the device's current location,
    /// requesting "when in use" authorization first if not yet determined.
    func currentLocation() async throws -> CLLocationCoordinate2D
}

enum LocationServiceError: Error, Equatable {
    case permissionDenied
    case restricted
    case unavailable
}

/// Wraps `CLLocationManager`'s delegate API behind `async/await`. Does a
/// single one-shot `requestLocation()` — no continuous tracking, since
/// route planning only needs one fix. If authorization is
/// `.notDetermined`, requests it in-context (the system prompt fires the
/// first time the user actually taps "Current Location," not at launch).
final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied:
            throw LocationServiceError.permissionDenied
        case .restricted:
            throw LocationServiceError.restricted
        @unknown default:
            throw LocationServiceError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authContinuation?.resume(returning: manager.authorizationStatus)
        authContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location.coordinate)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: LocationServiceError.unavailable)
        locationContinuation = nil
    }
}
```

This file has no test — it's a thin `CLLocationManager` wrapper, build-verify-only per the Global Constraints above (same convention as `APIClient`'s real networking, which also has no direct unit test — only its protocol's consumers are tested via mocks).

- [ ] **Step 2: Create the test mock**

Create `CycleStreets Ride PlannerTests/Location/MockLocationService.swift`:

```swift
//
//  MockLocationService.swift
//  CycleStreets Ride PlannerTests
//

import CoreLocation
@testable import CycleStreets_Ride_Planner

final class MockLocationService: LocationServiceProtocol {
    var coordinateToReturn = CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218)
    var errorToThrow: Error?

    func currentLocation() async throws -> CLLocationCoordinate2D {
        if let errorToThrow { throw errorToThrow }
        return coordinateToReturn
    }
}
```

- [ ] **Step 3: Update `MapViewModelTests`' shared setup and write the first failing test**

In `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`, replace:

```swift
    let client: MockAPIClient
    let vm: MapViewModel

    init() {
        client = MockAPIClient()
        vm = MapViewModel(apiClient: client)
    }
```

with:

```swift
    let client: MockAPIClient
    let locationService: MockLocationService
    let vm: MapViewModel

    init() {
        client = MockAPIClient()
        locationService = MockLocationService()
        vm = MapViewModel(apiClient: client, locationService: locationService)
    }
```

Then add this test (it will fail to compile because `MapViewModel` has no `useCurrentLocation` method and no `locationService` init parameter yet):

```swift
    @Test func testUseCurrentLocationAsFromSetsPlaceNamedCurrentLocation() async {
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        await vm.useCurrentLocation(as: .from)
        #expect(vm.fromPlace?.name == "Current Location")
        #expect(vm.fromPlace?.coordinate.latitude == 51.5)
        #expect(vm.fromPlace?.coordinate.longitude == -0.1)
        // Only .from is set (no .to yet), so planRoute never runs — isLoading
        // must still end up false, not get stuck true waiting for a
        // planRoute that was never going to happen.
        #expect(!vm.isLoading)
    }
```

- [ ] **Step 4: Run test to verify it fails**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests/testUseCurrentLocationAsFromSetsPlaceNamedCurrentLocation`
Expected: build FAILS — `MapViewModel` has no member `useCurrentLocation` and no init parameter `locationService`, and `MockLocationService` doesn't exist as a type the test file can resolve against `LocationServiceProtocol` (it does exist as a file, but `MapViewModel`'s init won't accept it yet).

- [ ] **Step 5: Add `locationService` to `MapViewModel` and implement `useCurrentLocation(as:)`**

In `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`, replace:

```swift
    var searchResults: [Place] = []
    var fromPlace: Place?
    var toPlace: Place?
    var routeOptions: [RouteOption] = []
    var selectedPlan: RoutePlan
    var isLoading = false
    var errorMessage: String?
    var searchDebounceMilliseconds: UInt64 = 300

    /// The active route among `routeOptions` — feeds `ItineraryView`, Save, and GPX export.
    var currentJourney: Journey? { routeOptions.first { $0.plan == selectedPlan }?.journey }

    private let apiClient: any APIClientProtocol
    private var searchDebounceTask: Task<Void, Never>?

    init(apiClient: any APIClientProtocol, initialSelectedPlan: RoutePlan = .balanced) {
        self.apiClient = apiClient
        self.selectedPlan = initialSelectedPlan
    }
```

with:

```swift
    var searchResults: [Place] = []
    var fromPlace: Place?
    var toPlace: Place?
    var routeOptions: [RouteOption] = []
    var selectedPlan: RoutePlan
    var isLoading = false
    var errorMessage: String?
    var isPresentingLocationPermissionAlert = false
    var searchDebounceMilliseconds: UInt64 = 300

    /// The active route among `routeOptions` — feeds `ItineraryView`, Save, and GPX export.
    var currentJourney: Journey? { routeOptions.first { $0.plan == selectedPlan }?.journey }

    private let apiClient: any APIClientProtocol
    private let locationService: any LocationServiceProtocol
    private var searchDebounceTask: Task<Void, Never>?

    init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, initialSelectedPlan: RoutePlan = .balanced) {
        self.apiClient = apiClient
        self.locationService = locationService
        self.selectedPlan = initialSelectedPlan
    }
```

Then add this method after `selectPlace(_:as:)` (the last method in the class, just before the closing `}`):

```swift

    /// Fetches the device's current location and assigns it to the given
    /// waypoint as a `Place` named literally "Current Location" — no
    /// reverse geocoding. Reuses `selectPlace(_:as:)` so planning, markers,
    /// and itinerary all behave exactly as they do for a searched place.
    /// On permission denial/restriction, sets
    /// `isPresentingLocationPermissionAlert` instead of `errorMessage` so
    /// `MapView` can offer a direct link to Settings.
    func useCurrentLocation(as role: WaypointRole) async {
        isLoading = true
        do {
            let coordinate = try await locationService.currentLocation()
            isLoading = false
            let place = Place(
                id: UUID().uuidString, name: "Current Location", near: nil,
                coordinate: Coordinate(longitude: coordinate.longitude, latitude: coordinate.latitude)
            )
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

`isLoading` is set back to `false` right after the location fetch resolves, *before* delegating to `selectPlace(_:as:)` — not left for `selectPlace`/`planRoute` to clear. This matters: `planRoute` (the only thing that would otherwise flip `isLoading` back to `false`) only runs once *both* waypoints are set. If `useCurrentLocation` left `isLoading = true` on the success path expecting `planRoute` to clear it, selecting current-location for just one waypoint (the other still unset) would leave the full-screen spinner stuck on forever. Because `planRoute`'s own first statement is `isLoading = true` with no suspension point before it, the `false` set here and the `true` set inside `planRoute` (when it does run) collapse into the same run-loop turn — no visible flicker, just a correct final state either way.

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests/testUseCurrentLocationAsFromSetsPlaceNamedCurrentLocation`
Expected: PASS

- [ ] **Step 7: Update `MapView.swift` and `RootView.swift` so the app target still compiles**

`MapViewModel.init` now requires a `locationService` argument — the app target's only call site (`MapView.init`) needs updating, and `RootView` needs to source a concrete `LocationService` from the environment. Wire this DI path fully now even though the UI in `MapView` doesn't yet call `useCurrentLocation` (that's Task 2) — the goal here is a green build, not a reachable feature.

In `CycleStreets Ride Planner/App/AppEnvironment.swift`, add at the end of the file:

```swift

private struct LocationServiceKey: EnvironmentKey {
    static let defaultValue: any LocationServiceProtocol = LocationService()
}

extension EnvironmentValues {
    var locationService: any LocationServiceProtocol {
        get { self[LocationServiceKey.self] }
        set { self[LocationServiceKey.self] = newValue }
    }
}
```

In `CycleStreets Ride Planner/Features/Map/MapView.swift`, replace the `init`:

```swift
    init(apiClient: any APIClientProtocol, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
        let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
        let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
        _vm = State(initialValue: MapViewModel(apiClient: apiClient, initialSelectedPlan: initialPlan))
        _pendingJourney = pendingJourney
        _pendingPlaceSelection = pendingPlaceSelection
    }
```

with:

```swift
    init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
        let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
        let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
        _vm = State(initialValue: MapViewModel(apiClient: apiClient, locationService: locationService, initialSelectedPlan: initialPlan))
        _pendingJourney = pendingJourney
        _pendingPlaceSelection = pendingPlaceSelection
    }
```

In `CycleStreets Ride Planner/App/RootView.swift`, replace:

```swift
struct RootView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var selectedTab: Tab = .map
    @State private var pendingMapJourney: Journey?
    @State private var pendingPlaceSelection: PendingPlaceSelection?

    enum Tab { case map, saved, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(apiClient: apiClient, pendingJourney: $pendingMapJourney, pendingPlaceSelection: $pendingPlaceSelection)
            }
```

with:

```swift
struct RootView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.locationService) private var locationService
    @State private var selectedTab: Tab = .map
    @State private var pendingMapJourney: Journey?
    @State private var pendingPlaceSelection: PendingPlaceSelection?

    enum Tab { case map, saved, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MapView(apiClient: apiClient, locationService: locationService, pendingJourney: $pendingMapJourney, pendingPlaceSelection: $pendingPlaceSelection)
            }
```

- [ ] **Step 8: Add the `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting**

This project uses `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_*` build settings instead of a checked-in `Info.plist`, so the usage-description string is a build-setting addition, not a plist edit. In `CycleStreets Ride Planner.xcodeproj/project.pbxproj`, there are two build configs for the app target (identifiable by `PRODUCT_BUNDLE_IDENTIFIER = "uk.slartibartfast.CycleStreets-Ride-Planner";` inside them) — one `name = Debug`, one `name = Release`. In **both**, add this line immediately after `GENERATE_INFOPLIST_FILE = YES;` (alphabetically before the existing `INFOPLIST_KEY_UI...` lines):

```
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "CycleStreets Ride Planner uses your location to plan routes starting from or ending at where you are.";
```

So each of the two configs' `buildSettings` block goes from:

```
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
```

to:

```
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "CycleStreets Ride Planner uses your location to plan routes starting from or ending at where you are.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
```

Do **not** touch any other build config block (the project-level configs and the two test-target configs don't have `PRODUCT_BUNDLE_IDENTIFIER` — leave those alone).

- [ ] **Step 9: Build the app target to confirm it compiles**

Run: `xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Add the remaining `useCurrentLocation` tests**

Add these tests to `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`, alongside the one from Step 3:

```swift
    @Test func testUseCurrentLocationAsToAfterFromTriggersPlanRoute() async {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = Place(id: "1", name: "Home", near: nil, coordinate: Coordinate(longitude: 0.1, latitude: 52.0))
        await vm.selectPlace(from, as: .from)
        await vm.useCurrentLocation(as: .to)
        #expect(vm.toPlace?.name == "Current Location")
        #expect(vm.currentJourney?.number == journey.number)
    }

    @Test func testUseCurrentLocationPermissionDeniedPresentsAlertAndDoesNotSetPlace() async {
        locationService.errorToThrow = LocationServiceError.permissionDenied
        await vm.useCurrentLocation(as: .from)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func testUseCurrentLocationRestrictedPresentsAlert() async {
        locationService.errorToThrow = LocationServiceError.restricted
        await vm.useCurrentLocation(as: .from)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
    }

    @Test func testUseCurrentLocationUnavailableSetsErrorMessage() async {
        locationService.errorToThrow = LocationServiceError.unavailable
        await vm.useCurrentLocation(as: .from)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
    }
```

- [ ] **Step 11: Run the full `MapViewModelTests` suite**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests`
Expected: ALL PASS — including every pre-existing test (none of them reference `locationService`, so they're unaffected beyond the shared `init()` change from Step 3).

If any test file's result looks stale, compare the `.xctest` bundle mtime under `DerivedData/.../Products/Debug-iphonesimulator/*.app/PlugIns/*.xctest` against the source file's mtime and `touch` the source file if the bundle is newer, then rerun.

- [ ] **Step 12: Update `docs/SPEC.md`**

Under `## Architecture`, replace:

```markdown
- Dependency injection: a single `any APIClientProtocol` is exposed via `EnvironmentValues.apiClient` (`App/AppEnvironment.swift`), built once from the bundled API key. Views/ViewModels take it as an init parameter rather than reading `@Environment` deep in the tree, except at the point of construction.
```

with:

```markdown
- Dependency injection: a single `any APIClientProtocol` is exposed via `EnvironmentValues.apiClient` (`App/AppEnvironment.swift`), built once from the bundled API key. `EnvironmentValues.locationService` (`any LocationServiceProtocol`, also in `AppEnvironment.swift`) follows the identical pattern. Views/ViewModels take these as init parameters rather than reading `@Environment` deep in the tree, except at the point of construction.
```

Under `### Map (`Features/Map/`)`, replace the `MapViewModel` bullet:

```markdown
- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `routeOptions`, `selectedPlan`, `currentJourney`, `isLoading`, `errorMessage`.
```

with:

```markdown
- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `routeOptions`, `selectedPlan`, `currentJourney`, `isLoading`, `errorMessage`, `isPresentingLocationPermissionAlert`.
  - `useCurrentLocation(as:)` — fetches the device's current location via `LocationServiceProtocol` (requesting "when in use" authorization in-context on first use, not at launch) and assigns it to the given `WaypointRole` as a `Place` named literally `"Current Location"` (no reverse geocoding), reusing `selectPlace(_:as:)` so planning/markers/itinerary behave identically to a searched place. On `.permissionDenied`/`.restricted` sets `isPresentingLocationPermissionAlert` instead of `errorMessage`, so the UI can offer a direct link to Settings; other failures set `errorMessage`. This `Place` is deliberately never added to `searchResults`, so it can never be bookmarked into `SavedLocation` storage under a name that goes stale.
```

(Leave the rest of the `MapViewModel` bullet's sub-list — `search`, `searchTextChanged`, `planRoute`, `clearRoute`, `loadJourney`, `selectPlace` — unchanged.)

Under `## Test coverage`, replace:

```markdown
`CycleStreets Ride PlannerTests/`: `Networking/{APIKeyTests, APIClientTests, GeocoderDecoderTests, JourneyPlanDecoderTests, MockAPIClient}`, `Features/{MapViewModelTests, ItineraryViewModelTests, SavedRoutesViewModelTests, MapStyleOptionTests}`, `Models/JourneyTests`, `Persistence/{RouteStoreTests, LocationStoreTests}`.

**Known gaps** (pure-SwiftUI-wiring or genuinely hard-to-unit-test, treated as build-verify-only per project convention): `SavedLocationsViewModel`, `SettingsView`, `GPXExportButton`, `ItineraryView`, `SavedRoutesView`, `Endpoints`, `MapStyleSheet`, `MapStyleThumbnail`.
```

with:

```markdown
`CycleStreets Ride PlannerTests/`: `Networking/{APIKeyTests, APIClientTests, GeocoderDecoderTests, JourneyPlanDecoderTests, MockAPIClient}`, `Features/{MapViewModelTests, ItineraryViewModelTests, SavedRoutesViewModelTests, MapStyleOptionTests}`, `Models/JourneyTests`, `Persistence/{RouteStoreTests, LocationStoreTests}`, `Location/{MockLocationService}`.

**Known gaps** (pure-SwiftUI-wiring or genuinely hard-to-unit-test, treated as build-verify-only per project convention): `SavedLocationsViewModel`, `SettingsView`, `GPXExportButton`, `ItineraryView`, `SavedRoutesView`, `Endpoints`, `MapStyleSheet`, `MapStyleThumbnail`, `LocationService` (the real `CLLocationManager` wrapper — not exercisable via `xcodebuild test` on a simulator without a simulated GPX location).
```

- [ ] **Step 13: Commit**

```bash
git add "CycleStreets Ride Planner/Location/LocationService.swift" \
  "CycleStreets Ride PlannerTests/Location/MockLocationService.swift" \
  "CycleStreets Ride Planner/App/AppEnvironment.swift" \
  "CycleStreets Ride Planner/Features/Map/MapViewModel.swift" \
  "CycleStreets Ride Planner/Features/Map/MapView.swift" \
  "CycleStreets Ride Planner/App/RootView.swift" \
  "CycleStreets Ride Planner.xcodeproj/project.pbxproj" \
  "CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift" \
  docs/SPEC.md
git commit -m "feat: add MapViewModel.useCurrentLocation backed by a new LocationService

Wraps CLLocationManager behind an async/await protocol matching the
APIClientProtocol DI pattern, requesting when-in-use authorization
in-context on first use rather than at launch. Reuses selectPlace(_:as:)
so a current-location waypoint plans/renders identically to a searched
one. Not yet reachable from the UI — MapView wiring is the next commit."
```

---

### Task 2: `MapView` — pinned "Current Location" row + permission alert

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Map/MapView.swift`
- Modify: `docs/SPEC.md`

This task is pure SwiftUI wiring (view layout + a button action) — per the Global Constraints above, this is build-verify-only, no unit test. Steps below are implement-then-build rather than TDD red/green.

**Interfaces:**
- Consumes: `MapViewModel.useCurrentLocation(as:) async` (Task 1), `MapViewModel.isPresentingLocationPermissionAlert: Bool` (Task 1), `MapView.updateCamera(to:)` (existing private method, unchanged), `MapView.selectingFor: WaypointRole` (existing `@State`, unchanged), `MapView.isSearchFieldFocused: FocusState<Bool>` (existing, unchanged).

- [ ] **Step 1: Change `resultsList`'s visibility condition so the dropdown shows on focus, not just on results**

In `CycleStreets Ride Planner/Features/Map/MapView.swift`, inside `body`, replace:

```swift
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
```

with:

```swift
                searchBar
                if isSearchFieldFocused { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
```

This is a deliberate behavior tightening, not just an enabler: previously, search results arriving after the field lost focus (e.g. the user tapped away mid-query) would still pop the dropdown back open; now the dropdown strictly follows focus.

- [ ] **Step 2: Add the pinned "Current Location" row to `resultsList`, and a `useCurrentLocation()` trigger method**

Replace the `resultsList` computed property:

```swift
    private var resultsList: some View {
        List(vm.searchResults) { place in
            HStack {
                Button {
                    selectPlace(place)
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.name).font(.body)
                        if let near = place.near {
                            Text(near).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    savedLocationsVM.save(name: place.name, coordinate: place.coordinate)
                    isPresentingLocationSavedConfirmation = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
```

with:

```swift
    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                useCurrentLocation()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Current Location")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .padding(.horizontal)

            if !vm.searchResults.isEmpty {
                Divider()
                List(vm.searchResults) { place in
                    HStack {
                        Button {
                            selectPlace(place)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(place.name).font(.body)
                                if let near = place.near {
                                    Text(near).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            savedLocationsVM.save(name: place.name, coordinate: place.coordinate)
                            isPresentingLocationSavedConfirmation = true
                        } label: {
                            Image(systemName: "bookmark")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxHeight: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
```

Note the "Current Location" row is a plain `Button`, not a `List` row — it is never added to `vm.searchResults` and has no bookmark icon, per this plan's Global Constraints.

Then add this method right after the existing `selectPlace(_:)` private method (same file, same access level):

```swift

    private func useCurrentLocation() {
        searchText = ""
        vm.searchResults = []
        let role = selectingFor
        if role == .from { selectingFor = .to }
        Task {
            await vm.useCurrentLocation(as: role)
            let resolvedPlace = role == .from ? vm.fromPlace : vm.toPlace
            if let resolvedPlace {
                withAnimation {
                    updateCamera(to: MKCoordinateRegion(
                        center: resolvedPlace.clCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
            if vm.fromPlace != nil && vm.toPlace != nil {
                isSearchFieldFocused = false
            }
        }
    }
```

This mirrors `selectPlace(_:)` exactly (clear search state, flip the From/To picker, recenter the camera once the waypoint is known, drop focus once both waypoints are set) — the only difference is the coordinate isn't known synchronously, so the camera recenter happens after the `await` instead of before it.

- [ ] **Step 3: Add the permission-denied alert**

In `body`, right after the existing `"Location Saved"` alert, add:

```swift
        .alert("Location Access Needed", isPresented: Binding(
            get: { vm.isPresentingLocationPermissionAlert },
            set: { vm.isPresentingLocationPermissionAlert = $0 }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Location access is off. Enable it in Settings to use Current Location.")
        }
```

So the full alert chain in `body` reads (unchanged alerts shown for context, don't re-type them if your editor lets you insert directly after the second `.alert`):

```swift
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Location Saved", isPresented: $isPresentingLocationSavedConfirmation) {
            Button("OK", role: .cancel) {}
        }
        .alert("Location Access Needed", isPresented: Binding(
            get: { vm.isPresentingLocationPermissionAlert },
            set: { vm.isPresentingLocationPermissionAlert = $0 }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Location access is off. Enable it in Settings to use Current Location.")
        }
```

`UIApplication`/`UIActivityViewController`-style UIKit types are already used elsewhere in this codebase (e.g. `GPXExportButton.swift`) with just `import SwiftUI` — no additional import needed here.

- [ ] **Step 4: Build to confirm it compiles, then manually verify in the simulator**

Run: `xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`
Expected: BUILD SUCCEEDED.

Then launch the app in the iPhone 17 simulator, tap into the Map screen's search field, and confirm:
- The "Current Location" row appears immediately (before typing anything).
- Tapping it prompts for location permission (first time only), then plans a route once both From and To are set, recentering the map.
- With location permission denied (Settings → Privacy → Location Services → this app → Never), tapping the row shows the "Location Access Needed" alert with a working "Open Settings" button.
- The row never appears with a bookmark icon, and doesn't show up in Saved Locations after being used.

- [ ] **Step 5: Update `docs/SPEC.md`**

Under `### Map (`Features/Map/`)`, replace the `MapView` bullet:

```markdown
- `MapView`: search bar with From/To segmented picker, results list (tap to select, bookmark icon to save as a Saved Location), map showing one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan, Start/End markers (green/red), "Clear" button, toolbar link to `ItineraryView` once a route exists. A bottom-right layers button opens `MapStyleSheet`, letting the user pick between 3 Apple styles and 3 OpenStreetMap-tile styles (persisted via `@AppStorage("mapStyle")`); route/marker rendering is duplicated between the Apple (`Map`/`MapPolyline`/`Marker`) and OSM (`MapLibreSwiftUI.MapView`/`ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer`) code paths since they're different underlying APIs. Tapping the map (not the search UI) dismisses the keyboard.
```

with:

```markdown
- `MapView`: search bar with From/To segmented picker, a results dropdown shown as soon as the search field is focused (not just once results arrive) — a pinned "Current Location" row at the top (no bookmark icon, deliberately never added to `searchResults` — see `MapViewModel.useCurrentLocation`), then the search-results list below it once non-empty (tap to select, bookmark icon to save as a Saved Location). Map shows one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan, Start/End markers (green/red), "Clear" button, toolbar link to `ItineraryView` once a route exists. A bottom-right layers button opens `MapStyleSheet`, letting the user pick between 3 Apple styles and 3 OpenStreetMap-tile styles (persisted via `@AppStorage("mapStyle")`); route/marker rendering is duplicated between the Apple (`Map`/`MapPolyline`/`Marker`) and OSM (`MapLibreSwiftUI.MapView`/`ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer`) code paths since they're different underlying APIs. A dedicated "Location Access Needed" alert (Cancel / Open Settings via `UIApplication.openSettingsURLString`) covers denied/restricted location permission, distinct from the generic error alert. Tapping the map (not the search UI) dismisses the keyboard.
```

Under `## Known limitations / roadmap`, replace:

```markdown
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names, "Current Location" via device location permissions.
```

with:

```markdown
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names. Zooming/centering the map to the device's current location (the other half of GitHub #6) is also not implemented — this feature only covers using Current Location as a route waypoint.
```

At the end of the file, add a new paragraph (matching the existing style of the OSM tile providers / multi-route-comparison entries):

```markdown

"Current Location" as a route waypoint (GitHub #6, route-planning half) is implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-07-26-current-location-search-design.md`; implementation plan: `docs/superpowers/plans/2026-08-01-current-location-search.md`.
```

- [ ] **Step 6: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapView.swift" docs/SPEC.md
git commit -m "feat: add pinned Current Location row to the Map search dropdown

Shows the dropdown as soon as the search field is focused rather than
only once results arrive, with a Current Location row pinned above
the search results. Tapping it drives the useCurrentLocation flow
added in the previous commit; denied/restricted permission surfaces a
dedicated alert with a direct link to Settings."
```

---

## Self-Review Notes

- **Spec coverage:** all design-spec decisions are covered — `LocationServiceProtocol`/`LocationServiceError`/`LocationService` (Task 1 Step 1), `EnvironmentValues.locationService` DI mirroring `apiClient` (Task 1 Step 7), `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting (Task 1 Step 8), `useCurrentLocation(as:)` + `isPresentingLocationPermissionAlert` with the literal "Current Location" name and no reverse geocoding (Task 1 Step 5), the never-in-`searchResults`/no-bookmark constraint (Task 2 Step 2 + Global Constraints), the dropdown-shows-on-focus UI change (Task 2 Step 1), the pinned row (Task 2 Step 2), the Settings-deep-link alert (Task 2 Step 3), reusing the existing full-screen `isLoading` spinner rather than new loading UI (Task 1 Step 5's `isLoading = true` at the top of `useCurrentLocation`), and mock-based testability matching the `MockAPIClient` convention (Task 1 Steps 2-3, 10).
- **Type consistency:** `LocationServiceProtocol.currentLocation() async throws -> CLLocationCoordinate2D`, `LocationServiceError` (`.permissionDenied`/`.restricted`/`.unavailable`), and `MapViewModel.useCurrentLocation(as role: WaypointRole) async` are named identically between Task 1 (producer) and Task 2 (consumer). `MapViewModel.init(apiClient:locationService:initialSelectedPlan:)` matches its Task 1 Step 7 call site in `MapView.init` exactly, which in turn matches its Task 1 Step 7 call site in `RootView.body` exactly.
- **No placeholders:** every step shows complete code, not descriptions of code.
