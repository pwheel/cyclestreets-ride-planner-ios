# UAT Findings — v1 (CycleStreets Ride Planner)

> Source plan: [`2026-06-11-cyclestreets-ride-planner-rewrite.md`](./2026-06-11-cyclestreets-ride-planner-rewrite.md)
> Found via manual simulator walkthrough after all 15 plan tasks + live API fixes were implemented and merged into `worktree-implement-plan`.

**For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement these fixes. Each finding below is scoped to be its own small task; follow TDD where the fix has testable logic (view models), and build-verify-only where it's pure SwiftUI wiring (matching the conventions established in the source plan).

---

## Finding 1: GPX Export is unreachable

**Status:** ✅ Fixed — commit `4bae78c`.

**Severity:** High — a fully-built, previously-approved feature (Task 9 of the source plan) is completely inaccessible to users.

**Symptom:** No "GPX Export" button anywhere in the UI.

**Root cause:** `GPXExportButton` lives in `ItineraryView`'s toolbar (`CycleStreets Ride Planner/Features/Itinerary/ItineraryView.swift`), but `ItineraryView` itself is never instantiated anywhere in production code — confirmed via `grep -rn "ItineraryView("` returning zero matches outside the test target. Task 7 (Map View) and Task 8 (Itinerary View) were each implemented and reviewed independently; nothing in either task's scope wired a navigation path from the planned route on the map to the itinerary screen. This gap was not flagged by either task's spec-compliance review because "wire ItineraryView into the Map flow" was never actually specified in the source plan — it's a hole in the plan itself, not an implementation defect against the plan as written.

**Suggested fix:** Add a way to reach `ItineraryView` from `MapView` once a route is planned — e.g. a "View Itinerary" button/`NavigationLink` that appears in `MapView`'s toolbar or overlay when `vm.currentJourney != nil`, pushing `ItineraryView(journey: journey)` via the existing `NavigationStack` in `RootView`.

**Files likely touched:** `Features/Map/MapView.swift`.

---

## Finding 2: Remove Account / sign-in

**Status:** ✅ Fixed — commit `c795811`.

**Severity:** Medium — descope, not a defect. The feature works as built (Task 12), but is not wanted.

**Symptom:** An "Account" tab presents a CycleStreets username/password sign-in form and Keychain-backed session.

**Decision:** The app is scoped to route planning only; CycleStreets account integration is out of scope.

**Suggested fix:** Remove the Account tab from `RootView` and delete the now-unused account feature entirely, rather than just hiding it — per this project's engineering conventions, unused code should be deleted, not left as dead weight:
- `Features/Account/` (`AccountView.swift`, `AccountViewModel.swift`, `KeychainHelper.swift`)
- `Models/UserSession.swift`
- `CycleStreets Ride PlannerTests/Features/AccountViewModelTests.swift`, `MockKeychainHelper.swift`
- `APIClientProtocol.login(username:password:)`, `APIClient.login(...)`, `Endpoints.login(...)`, and the corresponding `MockAPIClient.login`/`tokenToReturn`/`login`-related test scaffolding
- The Account tab block in `App/RootView.swift`

**Open question:** Confirm the CycleStreets API key itself doesn't require an authenticated session for route planning/geocoding/GPX export (it doesn't — this was verified live in the API-fixes work; all three endpoints work with just the API key, no user login).

---

## Finding 3: Saved Routes / Saved Locations have no way to save anything

**Status:** ✅ Fixed — commit `4bae78c`. A follow-up UAT pass found saved routes also couldn't be *reopened*; that gap is fixed too, in commit `a17913f` (see `SavedRoutesViewModel.reload(route:)`). A second follow-up below (loading a saved route doesn't show it on the map) is still **Open**.

### Follow-up 3b: Loading a saved route doesn't show it on the Map

**Status:** ✅ Fixed — commit `62227d3`. Landed a lighter-weight version of the suggested fix: rather than fully hoisting `MapViewModel` to `RootView`, added `MapViewModel.loadJourney(_:)` (tested) plus a `Binding<Journey?>` "pending journey" hand-off threaded from `RootView` into `MapView`, with `SavedRoutesView` reporting a loaded journey via a callback (`onJourneyLoaded`) rather than reaching into `RootView`'s state directly. `MapView` still owns its own `MapViewModel` instance.

**Symptom:** Tapping a saved route in `SavedRoutesView` reloads the journey and pushes straight to `ItineraryView` (turn-by-turn list only). There's no way to see the route drawn on the map — the polyline/marker rendering only exists in `MapView`, and `SavedRoutesView`'s reload never touches it. Expected: loading a saved route should land on the Map view with the route plotted, exactly as if the user had just searched and planned it fresh (with `ItineraryView` still reachable from there via the existing "Itinerary" toolbar link).

**Root cause / why this isn't a small tweak:** `MapView` currently owns its `MapViewModel` privately — `@State private var vm: MapViewModel`, constructed fresh inside `MapView.init(apiClient:)` (`CycleStreets Ride Planner/Features/Map/MapView.swift`). Nothing outside `MapView` can reach into it. Separately, `RootView`'s `TabView` (`CycleStreets Ride Planner/App/RootView.swift`) has no `selection` binding, so there's no way to programmatically switch to the Map tab from the Saved tab either. Fixing this properly needs both:
1. **Hoisting `MapViewModel`** up to somewhere shared (e.g. owned by `RootView`, injected into `MapView` instead of created by it) so `SavedRoutesView`'s reload action can populate `currentJourney` on the same instance `MapView` renders.
2. **A `TabView(selection:)` binding** in `RootView` so tapping a saved route can switch to the Map tab, not just push a new screen within the Saved tab's own `NavigationStack`.

**Secondary wrinkle:** `SavedRoute` only stores `journeyID`/`plan`/`name`/`distanceMetres`/`timeSeconds` — no start/end place data — so `MapViewModel.fromPlace`/`toPlace` (type `Place`, used for the green/red markers) can't be reconstructed with real names from a saved route alone. This is less of a blocker than it sounds: `MapView`'s markers already use hardcoded literal titles ("Start"/"End", not `place.name` — see `Marker("Start", coordinate: from.clCoordinate)` in `MapView.swift`), so a synthetic `Place` built from the reloaded journey's first/last coordinate (`journey.allCoordinates.first`/`.last`) would be enough to get correct marker positions; only `currentJourney` (for the polyline) actually needs the full journey data, which the reload already fetches.

**Files likely touched:** `App/RootView.swift` (state hoisting + tab selection), `Features/Map/MapView.swift` (accept an injected `MapViewModel` instead of constructing its own), `Features/SavedRoutes/SavedRoutesView.swift` / `SavedRoutesViewModel.swift` (reload should populate the shared `MapViewModel` and trigger the tab switch, rather than — or perhaps in addition to — navigating to `ItineraryView` directly).

**Severity:** High — like Finding 1, a built feature (Task 10 Persistence Layer, Task 11 Saved Routes & Locations Views) is present but functionally dead.

**Symptom:** The "Saved" tab shows (empty) "Saved Routes" and "Saved Locations" lists, but there is no button anywhere in the app to actually save a route or a location.

**Root cause:** `SavedRoutesViewModel.save(journey:name:)` and `SavedLocationsViewModel.save(name:coordinate:)` both exist and are unit-testable, but confirmed via `grep -rn "\.save(journey\|\.save(name:"` that neither is ever called from production UI code. No task in the source plan specified adding a "Save this route" or "Save this location" affordance to `MapView`/`ItineraryView` — same class of plan gap as Finding 1.

**Suggested fix:**
- Add a "Save Route" action (e.g. in `ItineraryView`'s toolbar, alongside GPX export, once Finding 1 is fixed) that calls `SavedRoutesViewModel.save(journey:name:)`, likely prompting for a name.
- Add a "Save Location" action to `MapView`'s search results or map long-press/marker context (e.g. on `fromPlace`/`toPlace` or a tapped map point) that calls `SavedLocationsViewModel.save(name:coordinate:)`.
- Consider whether `SavedRoutesViewModel`/`SavedLocationsViewModel` should be shared (via `@Environment` or passed in) between `MapView`/`ItineraryView` and `SavedRoutesView`/`SavedLocationsView`, rather than each view owning its own instance — currently each view creates its own `@State private var vm = ...ViewModel()`, backed by the same on-disk store, so saves from one screen would require the other screen to reload (`.onAppear { vm.load() }` already does this correctly for `SavedRoutesView`/`SavedLocationsView`, so no additional wiring is needed there — just confirm this refresh-on-appear behavior is sufficient).

**Files likely touched:** `Features/Map/MapView.swift`, `Features/Itinerary/ItineraryView.swift`.

---

## Finding 4: Saved Locations can't be used to prefill a route

**Status:** ✅ Fixed — commit `5dae093`. Tapping a saved location now prompts "Start (From)" / "Destination (To)" and hands off to `MapView` via the same `RootView` cross-tab plumbing built for Follow-up 3b, reusing that pattern rather than hoisting `MapViewModel` itself.

**Severity:** Medium — same class of gap as Finding 3 (save action shipped, but the reciprocal "use it" action never did), just for locations rather than routes.

**Symptom:** `SavedLocationsView` (`CycleStreets Ride Planner/Features/SavedLocations/SavedLocationsView.swift`) lists saved locations with a name and lat/lon, but rows have no tap action at all — confirmed by reading the file, the `ForEach` body is a plain `HStack`, not a `Button`/`NavigationLink`. There's no way to pick a saved location as the "from" or "to" point for a new route.

**Suggested fix:** Add a way to select a saved location from `SavedLocationsView` and feed it into `MapView`'s `fromPlace`/`toPlace` — e.g. tapping a row could dismiss back to the Map tab with the location pre-filled, or `MapView`'s search flow could offer "choose from saved locations" alongside geocoder search. Needs a bit of navigation-flow design since `SavedLocationsView` and `MapView` currently live in separate tabs with no shared state — likely worth resolving alongside the `MapViewModel` hoisting + `TabView(selection:)` work described in Follow-up 3b above, since both need the same cross-tab plumbing.

**Files likely touched:** `Features/SavedLocations/SavedLocationsView.swift`, `Features/Map/MapView.swift`, `Features/Map/MapViewModel.swift`, `App/RootView.swift` (tab-switching).

---

## Finding 5: Search typeahead only fires on submit

**Status:** ✅ Fixed — commit `f3dfb07`, with two follow-up bugfixes in commit `a56dc58` after device testing surfaced a regression the simulator/mock-backed tests didn't catch.

**Severity:** Medium — the search field works, but the UX reads as broken: nothing happens while typing, results only appear after the user explicitly taps the keyboard's search button.

**Symptom:** In `MapView`'s search bar, suggestions from the CycleStreets geocoder only appeared after the user submitted the text field (`.onSubmit`); no live typeahead as characters were entered.

**Root cause:** `MapView`'s `TextField` only wired `.onSubmit { Task { await vm.search(query: searchText) } }` — there was no `.onChange(of: searchText)` handler at all, confirmed by reading `MapView.swift`.

**Fix (commit `f3dfb07`):** Added `MapViewModel.searchTextChanged(_:)`, which debounces (default 300ms, exposed as `searchDebounceMilliseconds` so tests can shrink it) before calling the existing `search(query:)`, cancelling any prior pending search via a stored `Task`. `MapView`'s search field now calls it from `.onChange(of: searchText)`, alongside the existing `.onSubmit` for an immediate explicit search.

**Regression found on-device (not caught by the initial test suite):** Typing at normal-to-fast speed on a real device showed an "Error: cancelled" alert on every keystroke, sourced from `-[RTIInputSystemClient ...]`-adjacent keyboard activity but actually caused by two separate bugs in `MapViewModel`:
1. `search(query:)` cancelled `searchDebounceTask` before making its network call — but when invoked *from within* that very debounce `Task`, this was the task cancelling itself, so the geocode request always failed with a cancellation error.
2. Even after removing that, a still-in-flight request from an older keystroke, legitimately cancelled by a newer keystroke's debounce timer superseding it, surfaced its resulting `URLError(.cancelled)`/`CancellationError` as a user-facing `errorMessage`.

Both bugs were invisible to `MockAPIClient` in the initial test suite because the mock's `geocode(query:)` didn't honor task cancellation at all (it just returned canned data unconditionally) — a textbook case of a mock hiding real async/concurrency behavior. Fixed in commit `a56dc58`:
- `search(query:)` no longer cancels the debounce task itself.
- `search(query:)` now checks `Task.isCancelled` after a thrown error and silently returns instead of setting `errorMessage` when the failure is due to this request being superseded.
- `MockAPIClient.geocode` now calls `Task.checkCancellation()` (matching real `URLSession` behavior) and supports a configurable `geocodeDelayMilliseconds` so tests can simulate cancellation of an in-flight (not just pending) request — this is what let a new regression test (`testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded`) actually reproduce the bug before the fix.

**Files touched:** `Features/Map/MapViewModel.swift`, `Features/Map/MapView.swift`, `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`, `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`.

---

## Finding 6: Tapping outside the search bar doesn't dismiss the keyboard

**Status:** ✅ Fixed — commit `a619f8c`, with a follow-up fix in commit `566c294` after device testing found a regression.

**Severity:** Medium — while the keyboard is up, the bottom tab bar is unreachable, blocking navigation to Saved/Settings.

**Symptom:** After focusing the map search field, tapping elsewhere on screen (including the bottom tab bar area) didn't dismiss the keyboard, so the tab bar couldn't be used until the keyboard was dismissed some other way.

**Fix (commit `a619f8c`):** Added `@FocusState private var isSearchFieldFocused: Bool` bound to the search `TextField` via `.focused(...)`, plus `.contentShape(Rectangle())` + `.onTapGesture { isSearchFieldFocused = false }` on `MapView`'s root `ZStack`.

**Regression found on-device:** Attaching the tap gesture to the whole `ZStack` put it in front of (and gesture-priority-ahead of) the search results list's row `Button`s, so tapping a typeahead suggestion to select it stopped working entirely.

**Fix (commit `566c294`):** Moved `.onTapGesture { isSearchFieldFocused = false }` off the root `ZStack` and onto just the `map` layer, which sits behind the search bar/results card. Taps on empty map area still dismiss the keyboard; taps on the search bar or result rows reach their own controls unobstructed.

**Files touched:** `Features/Map/MapView.swift`.

---

## Finding 7: "Clear" on the map leaves the From/To picker on "To"

**Status:** ✅ Fixed — commit `a619f8c`.

**Severity:** Low — cosmetic/UX papercut, not a functional blocker, but confusing when starting a fresh search after clearing.

**Symptom:** After planning a route and hitting "Clear", the From/To segmented picker stayed on "To" (wherever it was left from the just-cleared route) instead of resetting to "From" for the next search.

**Root cause:** `MapViewModel.clearRoute()` resets `currentJourney`/`fromPlace`/`toPlace`/`searchResults`/`errorMessage`, but `selectingFor` is a private `@State` on `MapView`, not part of the view model, so `clearRoute()` had no way to reset it.

**Fix:** `MapView`'s Clear button action now also sets `selectingFor = .from` alongside `vm.clearRoute()`.

**Files touched:** `Features/Map/MapView.swift`.

---

## Summary Table

| # | Finding | Type | Priority | Status |
|---|---|---|---|---|
| 1 | GPX Export unreachable (ItineraryView never pushed to) | Bug (plan gap) | High | ✅ Fixed |
| 2 | Remove Account / sign-in | Descope | Medium | ✅ Fixed |
| 3 | Saved Routes/Locations have no save action (+ routes couldn't be reopened) | Bug (plan gap) | High | ✅ Fixed |
| 3b | Loading a saved route doesn't show it on the Map | Bug (plan gap) | Medium | ✅ Fixed |
| 4 | Saved Locations can't be used to prefill a route | Bug (plan gap) | Medium | ✅ Fixed |
| 5 | Search typeahead only fires on submit | Bug (plan gap) | Medium | ✅ Fixed |
| 6 | Tapping outside search bar doesn't dismiss keyboard | Bug (plan gap) | Medium | ✅ Fixed |
| 7 | "Clear" leaves From/To picker on "To" | Bug (plan gap) | Low | ✅ Fixed |

A further item from UAT (show Quietest/Balanced/Fastest simultaneously on the map) is new scope, not a defect against the existing plan — tracked separately in [`2026-07-19-roadmap-multi-route-comparison.md`](./2026-07-19-roadmap-multi-route-comparison.md).
