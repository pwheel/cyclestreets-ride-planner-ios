# Multi-Route Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show all three CycleStreets route plans (Quietest/Balanced/Fastest) on the map simultaneously instead of one at a time, with a tappable legend to pick the active one.

**Architecture:** `MapViewModel` fetches all 3 plans concurrently (`async let`, since the 3 cases are fixed and known — no `TaskGroup` needed) into a `routeOptions: [RouteOption]` array, replacing the old single `currentJourney`/`routePlan` fields. `currentJourney` becomes a computed property derived from `routeOptions` + `selectedPlan`, so every existing consumer (`ItineraryView` link, GPX export, Save) keeps working unchanged. `MapView` renders one colored polyline per successfully-fetched plan (selected one drawn heavier) plus a legend/chip row for selection.

**Tech Stack:** SwiftUI, `@Observable` (Observation framework), Swift Testing (`import Testing`, `@Test`, `#expect`), Swift structured concurrency (`async let`).

## Global Constraints

- **Swift Testing, not XCTest**: `import Testing`, `@Test func ...`, `#expect(...)` (per `CLAUDE.md`).
- **TDD**: write the failing test, confirm it fails for the right reason, implement minimally, confirm green (per `CLAUDE.md`).
- Pure-SwiftUI-wiring changes (view layout, tap-to-select-plan) are build-verify-only — no unit test required for `MapView` itself, per `docs/SPEC.md` → Test coverage convention.
- `docs/SPEC.md` must be updated in the same commit as any change that materially changes a screen or ViewModel contract (per `CLAUDE.md`).
- Build/test command: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17"`.
- **Stale incremental build gotcha:** if a changed test file's result looks unchanged, compare the `.xctest` bundle mtime against the source file mtime and `touch` the source file if the bundle is newer (per `CLAUDE.md`).

---

## File Structure

- **Modify:** `CycleStreets Ride Planner/Features/Map/MapViewModel.swift` — replaces `routePlan`/`currentJourney` stored fields with `routeOptions`/`selectedPlan` + computed `currentJourney`; rewrites `planRoute(from:to:)` to fetch all 3 plans concurrently; updates `clearRoute()`/`loadJourney(_:)` to match the new model.
- **Modify:** `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift` — adds per-plan override dictionaries (`journeysByPlan`, `errorsByPlan`) so tests can express "plan X succeeds, plan Y fails."
- **Modify:** `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift` — updates/adds tests for the new concurrent-fetch behavior.
- **Modify:** `CycleStreets Ride Planner/Features/Map/MapView.swift` — draws one polyline per fetched plan (color + stroke weight), adds a legend/chip row for plan selection, seeds `MapViewModel`'s initial `selectedPlan` from the `"defaultRoutePlan"` `UserDefaults` key.
- **Modify:** `docs/SPEC.md` — Map screen `MapViewModel` bullet (Task 1 commit), Map screen `MapView` bullet + Settings section + "Known limitations / roadmap" line (Task 2 commit).

---

### Task 1: `MapViewModel` — concurrent 3-plan fetch + `RouteOption` model

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`
- Modify: `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`
- Modify: `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Produces (used by Task 2): `MapViewModel.routeOptions: [RouteOption]` (ordered `.quietest, .balanced, .fastest`), `MapViewModel.selectedPlan: RoutePlan` (settable), `MapViewModel.currentJourney: Journey?` (computed, unchanged type/name from before), `RouteOption` struct with `plan: RoutePlan`, `journey: Journey?`, `errorMessage: String?`, conforming to `Identifiable` (`id == plan`) and `Equatable`. `MapViewModel.init(apiClient:initialSelectedPlan:)` — `initialSelectedPlan` defaults to `.balanced`.
- Consumes: `APIClientProtocol.planJourney(from:to:plan:) async throws -> Journey` (unchanged signature), `RoutePlan` (`Models/Journey.swift`, unchanged: `.balanced`/`.quietest`/`.fastest`, `CaseIterable`, `.displayName`).

- [ ] **Step 1: Extend `MockAPIClient` with per-plan overrides, and write the first failing test against `MapViewModel`**

Modify `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`: add two new stored properties and use them in `planJourney`, keeping the existing global `journeyToReturn`/`shouldThrow` as fallbacks so no existing test call site needs to change.

```swift
final class MockAPIClient: APIClientProtocol {
    var journeyToReturn: Journey?
    var placesToReturn: [Place] = []
    var gpxDataToReturn = Data("gpx content".utf8)
    var shouldThrow: Error?
    var geocodeQueriesReceived: [String] = []
    var geocodeDelayMilliseconds: UInt64 = 0
    var journeysByPlan: [RoutePlan: Journey] = [:]
    var errorsByPlan: [RoutePlan: Error] = [:]

    private func checkThrow() throws {
        if let e = shouldThrow { throw e }
    }

    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey {
        if let error = errorsByPlan[plan] { throw error }
        try checkThrow()
        return journeysByPlan[plan] ?? journeyToReturn ?? makeJourney(plan: plan)
    }
    // ... geocode, downloadGPX, reloadJourney, makeJourney unchanged ...
}
```

In `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`, add this test (it will fail to compile because `initialSelectedPlan` doesn't exist yet):

```swift
    @Test func testInitSetsSelectedPlanFromInitialValue() {
        let vm2 = MapViewModel(apiClient: client, initialSelectedPlan: .fastest)
        #expect(vm2.selectedPlan == .fastest)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests/testInitSetsSelectedPlanFromInitialValue`
Expected: build FAILS — `MapViewModel` has no member `selectedPlan` and no init parameter `initialSelectedPlan`.

- [ ] **Step 3: Replace `MapViewModel`'s data model and `planRoute` with the concurrent 3-plan version**

Replace the full contents of `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`:

```swift
//
//  MapViewModel.swift
//  CycleStreets Ride Planner
//

import Foundation
import CoreLocation
import Observation

enum WaypointRole: Equatable { case from, to }

/// A place selected outside `MapView`'s own search flow (e.g. from
/// Saved Locations), paired with which waypoint it should fill.
struct PendingPlaceSelection: Equatable {
    let place: Place
    let role: WaypointRole
}

/// One of the three concurrently-fetched route plans shown on the map at
/// once. `journey` is nil and `errorMessage` is set when that plan's
/// request failed.
struct RouteOption: Identifiable, Equatable {
    var id: RoutePlan { plan }
    let plan: RoutePlan
    var journey: Journey?
    var errorMessage: String?
}

@Observable
@MainActor
final class MapViewModel {
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

    /// Called as the user types in the search field to provide typeahead
    /// suggestions, debouncing so each keystroke doesn't fire its own
    /// network request.
    func searchTextChanged(_ text: String) {
        searchDebounceTask?.cancel()
        guard !text.isEmpty else { searchResults = []; return }
        let milliseconds = searchDebounceMilliseconds
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            await search(query: text)
        }
    }

    /// Fetches all 3 route plans concurrently and shows them together. If
    /// the currently selected plan's request fails but another succeeds,
    /// falls back to the first successful plan in quietest/balanced/fastest
    /// order, so a partially-successful fetch never leaves nothing selected.
    func planRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        isLoading = true
        async let quietest = fetchOption(.quietest, from: from, to: to)
        async let balanced = fetchOption(.balanced, from: from, to: to)
        async let fastest = fetchOption(.fastest, from: from, to: to)
        routeOptions = [await quietest, await balanced, await fastest]
        if routeOptions.first(where: { $0.plan == selectedPlan })?.journey == nil,
           let fallback = routeOptions.first(where: { $0.journey != nil }) {
            selectedPlan = fallback.plan
        }
        isLoading = false
    }

    private func fetchOption(_ plan: RoutePlan, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteOption {
        do {
            let journey = try await apiClient.planJourney(from: from, to: to, plan: plan)
            return RouteOption(plan: plan, journey: journey, errorMessage: nil)
        } catch {
            return RouteOption(plan: plan, journey: nil, errorMessage: error.localizedDescription)
        }
    }

    func clearRoute() {
        routeOptions = []
        fromPlace = nil
        toPlace = nil
        searchResults = []
        errorMessage = nil
    }

    /// Populates the map from a journey obtained outside the normal
    /// search flow (e.g. a reloaded saved route), deriving placeholder
    /// from/to markers from the journey's own coordinates since no
    /// searched `Place` exists for it. Shows only that one journey — does
    /// not fetch comparison routes for the other two plans, since reloading
    /// a specific saved route is a distinct flow from fresh planning.
    func loadJourney(_ journey: Journey) {
        routeOptions = [RouteOption(plan: journey.plan, journey: journey, errorMessage: nil)]
        selectedPlan = journey.plan
        searchResults = []
        errorMessage = nil
        let coordinates = journey.allCoordinates
        if let start = coordinates.first {
            fromPlace = Place(id: UUID().uuidString, name: "Start", near: nil,
                               coordinate: Coordinate(longitude: start.longitude, latitude: start.latitude))
        }
        if let end = coordinates.last {
            toPlace = Place(id: UUID().uuidString, name: "End", near: nil,
                             coordinate: Coordinate(longitude: end.longitude, latitude: end.latitude))
        }
    }

    /// Assigns a place to the given waypoint and, once both from and to
    /// are set, plans the route — matching the behavior of picking a
    /// place from search results.
    func selectPlace(_ place: Place, as role: WaypointRole) async {
        switch role {
        case .from: fromPlace = place
        case .to: toPlace = place
        }
        if let from = fromPlace, let to = toPlace {
            await planRoute(from: from.clCoordinate, to: to.clCoordinate)
        }
    }
}
```

- [ ] **Step 4: Run the new test to verify it passes**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests/testInitSetsSelectedPlanFromInitialValue`
Expected: PASS.

- [ ] **Step 5: Replace `testPlanRouteErrorSetsErrorMessage` with an all-plans-fail test, since the shared `errorMessage` is no longer touched by `planRoute`**

In `MapViewModelTests.swift`, delete this existing test:

```swift
    @Test func testPlanRouteErrorSetsErrorMessage() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.errorMessage != nil)
    }
```

Replace it with:

```swift
    @Test func testPlanRouteAllPlansFailLeavesCurrentJourneyNil() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.currentJourney == nil)
        #expect(vm.routeOptions.count == 3)
        #expect(vm.routeOptions.allSatisfy { $0.journey == nil && $0.errorMessage != nil })
        #expect(vm.errorMessage == nil)
    }
```

- [ ] **Step 6: Run it to verify it fails for the right reason, then confirm it passes**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests/testPlanRouteAllPlansFailLeavesCurrentJourneyNil`
Expected: first run FAILS (old `MapViewModel.swift` hasn't been in place before Step 3 — since Step 3 already replaced the file, this should now PASS immediately; if it doesn't, re-check Step 3's implementation against the code above before proceeding).

- [ ] **Step 7: Add the remaining `planRoute` scenario tests (all-succeed, partial-failure-with-fallback, partial-failure-without-fallback)**

Add to `MapViewModelTests.swift`:

```swift
    @Test func testPlanRouteAllPlansSucceedPopulatesRouteOptions() async {
        client.journeysByPlan = [
            .quietest: client.makeJourney(plan: .quietest),
            .balanced: client.makeJourney(plan: .balanced),
            .fastest: client.makeJourney(plan: .fastest)
        ]
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.routeOptions.count == 3)
        #expect(vm.routeOptions.allSatisfy { $0.journey != nil })
        #expect(vm.currentJourney?.plan == .balanced)
    }

    @Test func testPlanRoutePartialFailureOnSelectedPlanFallsBackToFirstSuccess() async {
        client.journeysByPlan = [
            .quietest: client.makeJourney(plan: .quietest),
            .fastest: client.makeJourney(plan: .fastest)
        ]
        client.errorsByPlan = [.balanced: NSError(domain: "Test", code: 1)]
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        #expect(vm.selectedPlan == .quietest)
        #expect(vm.currentJourney?.plan == .quietest)
    }

    @Test func testPlanRoutePartialFailureOnNonSelectedPlanKeepsSelection() async {
        client.journeysByPlan = [
            .balanced: client.makeJourney(plan: .balanced),
            .quietest: client.makeJourney(plan: .quietest)
        ]
        client.errorsByPlan = [.fastest: NSError(domain: "Test", code: 1)]
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        #expect(vm.selectedPlan == .balanced)
        #expect(vm.currentJourney?.plan == .balanced)
        let fastestOption = vm.routeOptions.first { $0.plan == .fastest }
        #expect(fastestOption?.journey == nil)
        #expect(fastestOption?.errorMessage != nil)
    }

    @Test func testSelectingDifferentPlanUpdatesCurrentJourney() async {
        client.journeysByPlan = [
            .quietest: client.makeJourney(plan: .quietest),
            .balanced: client.makeJourney(plan: .balanced),
            .fastest: client.makeJourney(plan: .fastest)
        ]
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        vm.selectedPlan = .fastest
        #expect(vm.currentJourney?.plan == .fastest)
    }

    @Test func testLoadJourneySetsSelectedPlanToJourneysPlan() {
        let journey = client.makeJourney(plan: .fastest)
        vm.loadJourney(journey)
        #expect(vm.selectedPlan == .fastest)
        #expect(vm.currentJourney == journey)
    }
```

Update the existing `testClearRouteResetsState` to also assert `routeOptions` is cleared:

```swift
    @Test func testClearRouteResetsState() async {
        client.journeyToReturn = client.makeJourney()
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        vm.clearRoute()
        #expect(vm.currentJourney == nil)
        #expect(vm.routeOptions.isEmpty)
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
    }
```

- [ ] **Step 8: Run the full `MapViewModelTests` suite**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:CycleStreets_Ride_PlannerTests/MapViewModelTests`
Expected: ALL PASS (including the pre-existing tests `testPlanRoutePopulatesJourney`, `testSelectPlaceAsToAfterFromTriggersPlanRoute`, `testSelectPlaceAsFromOnlySetsFromPlace`, `testLoadJourneySetsCurrentJourney`, `testLoadJourneyDerivesFromAndToPlacesFromCoordinates`, `testLoadJourneyClearsSearchResultsAndError`, and all `searchTextChanged`/`search` tests — none of these reference the removed `routePlan` field, so they're unaffected by this task).

If any test file's result looks stale (e.g. a deleted test still appears to run), compare the `.xctest` bundle mtime under `DerivedData/.../Products/Debug-iphonesimulator/*.app/PlugIns/*.xctest` against `MapViewModelTests.swift`'s mtime and `touch` the source file if the bundle is newer, then rerun.

- [ ] **Step 9: Update `docs/SPEC.md`'s `MapViewModel` bullet to match the new contract**

In `docs/SPEC.md`, under `### Map (`Features/Map/`)`, replace:

```markdown
- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `currentJourney`, `isLoading`, `errorMessage`, `routePlan`.
  - `search(query:)` — immediate geocode; ignores cancellation errors (a superseded in-flight request from a stale keystroke is not a user-facing error — see `searchTextChanged`).
  - `searchTextChanged(_:)` — debounced (default 300ms, `searchDebounceMilliseconds` is injectable for tests) typeahead; cancels the prior pending search on each new keystroke.
  - `planRoute(from:to:)`, `clearRoute()`.
  - `loadJourney(_:)` — populates the map from a journey obtained outside the normal search flow (a reloaded saved route); synthesizes placeholder from/to `Place`s from the journey's own first/last coordinate since no searched `Place` exists for it.
  - `selectPlace(_:as:)` — assigns a `Place` to `.from`/`.to` (`WaypointRole`); once both are set, calls `planRoute`. Used both by tapping a search result and by the Saved Locations cross-tab hand-off.
```

with:

```markdown
- `MapViewModel`: `searchResults`, `fromPlace`/`toPlace`, `routeOptions`, `selectedPlan`, `currentJourney`, `isLoading`, `errorMessage`.
  - `routeOptions: [RouteOption]` — always 3 entries after a plan attempt (`.quietest, .balanced, .fastest` order), each holding that plan's `journey: Journey?` and `errorMessage: String?` (nil journey + non-nil errorMessage means that plan's request failed). `currentJourney` is computed from `routeOptions.first { $0.plan == selectedPlan }?.journey` — feeds `ItineraryView`, Save, and GPX export exactly as before.
  - `search(query:)` — immediate geocode; ignores cancellation errors (a superseded in-flight request from a stale keystroke is not a user-facing error — see `searchTextChanged`).
  - `searchTextChanged(_:)` — debounced (default 300ms, `searchDebounceMilliseconds` is injectable for tests) typeahead; cancels the prior pending search on each new keystroke.
  - `planRoute(from:to:)` — fetches all 3 `RoutePlan`s concurrently (`async let`, one `apiClient.planJourney` call per plan). Per-plan failures are captured in that plan's `RouteOption.errorMessage`, not the shared `errorMessage` (which remains reserved for `search(query:)` failures). If `selectedPlan`'s own request fails but another succeeds, `selectedPlan` auto-falls-back to the first successful plan in `.quietest, .balanced, .fastest` order.
  - `clearRoute()` — resets `routeOptions` to `[]` (plus from/to/search state, as before).
  - `loadJourney(_:)` — populates the map from a journey obtained outside the normal search flow (a reloaded saved route); sets `routeOptions` to a single entry for that journey's own plan (no comparison fetch of the other two plans — reloading a saved route is a distinct flow from fresh planning) and sets `selectedPlan` to match. Synthesizes placeholder from/to `Place`s from the journey's own first/last coordinate since no searched `Place` exists for it.
  - `selectPlace(_:as:)` — assigns a `Place` to `.from`/`.to` (`WaypointRole`); once both are set, calls `planRoute`. Used both by tapping a search result and by the Saved Locations cross-tab hand-off.
```

- [ ] **Step 10: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapViewModel.swift" "CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift" "CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift" docs/SPEC.md
git commit -m "feat: fetch all 3 route plans concurrently in MapViewModel

Replaces the single routePlan/currentJourney fields with routeOptions
(one RouteOption per plan) and a computed currentJourney derived from
selectedPlan, so ItineraryView/Save/GPX export keep working unchanged.
Partial per-plan failures are captured per-RouteOption rather than the
shared errorMessage; a failed selected plan falls back to the first
successful one."
```

---

### Task 2: `MapView` — legend/chip row + per-plan polyline rendering

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Map/MapView.swift`
- Modify: `docs/SPEC.md`

**Interfaces:**
- Consumes (from Task 1): `MapViewModel.routeOptions: [RouteOption]`, `MapViewModel.selectedPlan: RoutePlan` (settable), `RouteOption.plan/journey/errorMessage`, `MapViewModel.init(apiClient:initialSelectedPlan:)`, `RoutePlan.displayName: String` (pre-existing, `Models/Journey.swift`).
- Produces: none (leaf UI task).

This task is pure SwiftUI wiring (view layout + tap-to-select) — per `docs/SPEC.md` → Test coverage convention this is build-verify-only, no unit test. Steps below are implement-then-build rather than TDD red/green.

- [ ] **Step 1: Add per-plan color helper and legend/chip row, replace the map's polyline rendering, and seed the initial selected plan from `defaultRoutePlan`**

Replace the full contents of `CycleStreets Ride Planner/Features/Map/MapView.swift`:

```swift
import SwiftUI
import MapKit

struct MapView: View {
    @State private var vm: MapViewModel
    @Environment(\.apiClient) private var apiClient
    @Binding var pendingJourney: Journey?
    @Binding var pendingPlaceSelection: PendingPlaceSelection?
    @State private var searchText = ""
    @State private var selectingFor: WaypointRole = .from
    @FocusState private var isSearchFieldFocused: Bool
    @State private var savedLocationsVM = SavedLocationsViewModel()
    @State private var isPresentingLocationSavedConfirmation = false
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    init(apiClient: any APIClientProtocol, pendingJourney: Binding<Journey?>, pendingPlaceSelection: Binding<PendingPlaceSelection?>) {
        let storedRawValue = UserDefaults.standard.string(forKey: "defaultRoutePlan") ?? RoutePlan.balanced.rawValue
        let initialPlan = RoutePlan(rawValue: storedRawValue) ?? .balanced
        _vm = State(initialValue: MapViewModel(apiClient: apiClient, initialSelectedPlan: initialPlan))
        _pendingJourney = pendingJourney
        _pendingPlaceSelection = pendingPlaceSelection
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 0) {
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Plan Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let journey = vm.currentJourney {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Itinerary") {
                        ItineraryView(journey: journey, apiClient: apiClient)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        vm.clearRoute()
                        selectingFor = .from
                    }
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView().scaleEffect(1.5) }
        }
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
        .onChange(of: pendingJourney) { _, newValue in
            guard let journey = newValue else { return }
            vm.loadJourney(journey)
            if let end = journey.allCoordinates.last {
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: end,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
            pendingJourney = nil
        }
        .onChange(of: pendingPlaceSelection) { _, newValue in
            guard let selection = newValue else { return }
            if selection.role == .from { selectingFor = .to }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            Task {
                await vm.selectPlace(selection.place, as: selection.role)
                pendingPlaceSelection = nil
            }
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(nonSelectedRouteOptions) { option in
                if let journey = option.journey {
                    MapPolyline(coordinates: journey.allCoordinates)
                        .stroke(color(for: option.plan), lineWidth: 3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                MapPolyline(coordinates: journey.allCoordinates)
                    .stroke(color(for: selectedOption.plan), lineWidth: 5)
            }
            if let from = vm.fromPlace {
                Marker("Start", coordinate: from.clCoordinate).tint(.green)
            }
            if let to = vm.toPlace {
                Marker("End", coordinate: to.clCoordinate).tint(.red)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
    }

    private var nonSelectedRouteOptions: [RouteOption] {
        vm.routeOptions.filter { $0.plan != vm.selectedPlan }
    }

    private func color(for plan: RoutePlan) -> Color {
        switch plan {
        case .quietest: return .green
        case .balanced: return .yellow
        case .fastest: return .red
        }
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            ForEach(vm.routeOptions) { option in
                Button {
                    vm.selectedPlan = option.plan
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: option.plan))
                            .frame(width: 10, height: 10)
                        Text(option.plan.displayName)
                        if option.errorMessage != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        option.plan == vm.selectedPlan ? Color.secondary.opacity(0.2) : Color.clear,
                        in: Capsule()
                    )
                }
                .disabled(option.journey == nil)
                .opacity(option.journey == nil ? 0.5 : 1)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                selectingFor == .from ? "Search start location" : "Search end location",
                text: $searchText
            )
            .submitLabel(.search)
            .focused($isSearchFieldFocused)
            .onSubmit { Task { await vm.search(query: searchText) } }
            .onChange(of: searchText) { _, newValue in vm.searchTextChanged(newValue) }
            if !searchText.isEmpty {
                Button { searchText = ""; vm.searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $selectingFor) {
                Text("From").tag(WaypointRole.from)
                Text("To").tag(WaypointRole.to)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

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

    private func selectPlace(_ place: Place) {
        searchText = ""
        vm.searchResults = []
        let role = selectingFor
        if role == .from { selectingFor = .to }
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
        Task { await vm.selectPlace(place, as: role) }
    }
}
```

- [ ] **Step 2: Build the app to verify it compiles and run the full test suite to confirm no regressions**

Run: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17"`
Expected: BUILD SUCCEEDED, all tests pass (this task adds no new unit tests — it's pure SwiftUI wiring per the Global Constraints above).

- [ ] **Step 3: Manually verify in the simulator**

Launch the app in the iPhone 17 simulator, search a start and end location (or tap two Saved Locations), and confirm: 3 colored polylines appear (green/yellow/red), the legend row shows 3 chips matching those colors, tapping a chip switches which polyline is drawn heavier and updates the "Itinerary" toolbar link's content, and Start/End markers still show as green/red as before.

- [ ] **Step 4: Update `docs/SPEC.md`'s `MapView` bullet, Settings section, and "Known limitations" line**

In `docs/SPEC.md`, under `### Map (`Features/Map/`)`, replace:

```markdown
- `MapView`: search bar with From/To segmented picker, results list (tap to select, bookmark icon to save as a Saved Location), map with polyline + Start/End markers, "Clear" button (also resets the From/To picker to "From"), toolbar link to `ItineraryView` once a route exists. Tapping the map (not the search UI) dismisses the keyboard.
```

with:

```markdown
- `MapView`: search bar with From/To segmented picker, results list (tap to select, bookmark icon to save as a Saved Location), map showing one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan (tapping a chip sets `selectedPlan`; a chip for a plan whose request failed is dimmed/disabled with a warning glyph), Start/End markers (green/red, matching the CycleStreets mobile website), "Clear" button (also resets the From/To picker to "From"), toolbar link to `ItineraryView` once a route exists. Tapping the map (not the search UI) dismisses the keyboard.
```

Under `### Settings (`Features/Settings/`)`, replace:

```markdown
`@AppStorage`-backed: `"defaultRoutePlan"` (default `.balanced`), `"useMetric"` (default `true`). Plus an About section (version, links).
```

with:

```markdown
`@AppStorage`-backed: `"defaultRoutePlan"` (default `.balanced`) — read by `MapView` at construction to seed `MapViewModel`'s initial `selectedPlan` (which of the 3 always-fetched route plans is pre-selected), not which plan is requested; `"useMetric"` (default `true`). Plus an About section (version, links).
```

Under `## Known limitations / roadmap`, replace:

```markdown
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: simultaneous multi-route comparison (quietest/balanced/fastest shown together), switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names, "Current Location" via device location permissions.
```

with:

```markdown
Not implemented, captured for future design in `docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`: switchable geocoder provider (CycleStreets vs MapKit, flag-based), editable saved-location names, "Current Location" via device location permissions.

Simultaneous multi-route comparison (quietest/balanced/fastest shown together) is implemented — see the Map screen section above. Design record: `docs/superpowers/specs/2026-07-25-multi-route-comparison-design.md`; implementation plan: `docs/superpowers/plans/2026-07-25-multi-route-comparison.md`.
```

- [ ] **Step 5: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapView.swift" docs/SPEC.md
git commit -m "feat: show all 3 route plans on the map with a legend to select one

Adds a colored polyline per successfully-fetched RoutePlan (green/
yellow/red) with the selected plan drawn heavier, plus a tappable
legend/chip row below the search bar. MapView now seeds MapViewModel's
initial selectedPlan from the defaultRoutePlan setting, fixing that
setting's previously-dead wiring."
```

---

## Self-Review Notes

- **Spec coverage:** all 5 decisions in the design spec are covered — default/concurrent fetch (Task 1 Step 3), partial-failure handling (Task 1 Steps 5/7), legend chip selection UX (Task 2 Step 1), color scheme incl. the green/yellow/red + unchanged green/red markers (Task 2 Step 1), `defaultRoutePlan` repurposed as pre-selection with its dead-wiring fix (Task 2 Step 1). The `loadJourney` scope boundary (no comparison fetch on saved-route reload) is implemented in Task 1 Step 3 and tested in Task 1 Step 7.
- **Type consistency:** `RouteOption`, `routeOptions: [RouteOption]`, `selectedPlan: RoutePlan`, `currentJourney: Journey?` are named identically between Task 1 (producer) and Task 2 (consumer). `MapViewModel.init(apiClient:initialSelectedPlan:)` matches its Task 2 call site exactly.
- **No placeholders:** every step shows complete code, not descriptions of code.
