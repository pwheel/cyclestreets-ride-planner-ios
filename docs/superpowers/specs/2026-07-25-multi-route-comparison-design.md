# Design: Multi-Route Comparison (Quietest / Balanced / Fastest)

> Resolves the open design questions in [`docs/superpowers/plans/2026-07-19-roadmap-multi-route-comparison.md`](../plans/2026-07-19-roadmap-multi-route-comparison.md), implementing GitHub issue [#4](https://github.com/pwheel/cyclestreets-ride-planner-ios/issues/4).

## The ask

The Map view currently plans and displays exactly one route at a time (whichever `RoutePlan` is active). Users want to see all three route options — Quietest, Balanced, Fastest — plotted simultaneously so they can visually compare and pick one, rather than re-planning one type at a time.

## Decisions made

Resolved during brainstorming (see roadmap doc's "Open design questions" for the original list):

1. **Default behavior, not opt-in.** Every `planRoute(from:to:)` call fetches all 3 plans concurrently and shows them together. The existing app has no plan-switcher UI on the Map screen today (confirmed via grep — `MapViewModel.routePlan` is set once at init and never changed from `MapView`), so this replaces the single hidden default-plan lookup rather than competing with an existing single-plan picker. Cost: 3x API calls per plan action, accepted as the price of the core ask.
2. **Partial failure: show what succeeded, flag the rest.** If 1-2 of the 3 requests fail, render whichever routes came back; the failed plan's legend chip shows a disabled/dimmed state with a warning glyph instead of blocking the working routes with an alert.
3. **Selection UX: legend/chip row.** A row of 3 tappable chips (color dot + plan name) selects which route is "active" (feeds Itinerary/Save/GPX). Chosen over tapping the polyline directly on the map, since SwiftUI `Map`'s polyline tap hit-testing is unreliable, especially where routes overlap.
4. **Visual differentiation: color-per-plan.** Quietest=green, Balanced=yellow, Fastest=red, matching the CycleStreets mobile website's route colors. The selected route is additionally drawn with a heavier stroke than the other two, so "active" is visually distinct without extra chrome. Start/End `Marker`s stay green/red — also matching the CycleStreets mobile website, and not considered a clash worth avoiding.
5. **`Settings.defaultRoutePlan` is repurposed as pre-selection.** It becomes "which chip is pre-selected when a route is first planned," rather than "the only plan requested." This setting is currently dead code — confirmed via grep that `MapViewModel.routePlan` is hardcoded to `.balanced` at declaration and never reads `@AppStorage("defaultRoutePlan")` — so wiring it up is in scope alongside the repurpose, not a separate fix.

## Data model & fetch strategy

Replace `MapViewModel`'s single `routePlan: RoutePlan` / `currentJourney: Journey?` pair with:

```swift
struct RouteOption: Identifiable {
    var id: RoutePlan { plan }
    let plan: RoutePlan
    var journey: Journey?
    var errorMessage: String?
}

var routeOptions: [RouteOption] = []   // always 3 entries after a plan attempt, ordered .quietest, .balanced, .fastest
var selectedPlan: RoutePlan
var currentJourney: Journey? { routeOptions.first { $0.plan == selectedPlan }?.journey }
```

`planRoute(from:to:)` fires all 3 requests concurrently using `async let` (three fixed, known cases — plain structured concurrency, no need for a `TaskGroup`), catching each plan's failure independently into its own `RouteOption.errorMessage` rather than surfacing to the existing shared `errorMessage` (which remains reserved for `search(query:)` failures — an unrelated flow).

**Selection fallback rule:** after a fetch, if `selectedPlan`'s own request failed but another plan succeeded, `selectedPlan` auto-updates to the first successful plan in `.quietest, .balanced, .fastest` order. This avoids a "route planned successfully, but nothing shown as active" dead end. If all 3 fail, `selectedPlan` is left unchanged and `currentJourney` is `nil` (no Itinerary toolbar link, matching existing `if let journey = vm.currentJourney` behavior) — no blocking alert; the 3 legend chips each show their own failed state.

**Considered and rejected:** a separate `comparisonJourneys: [RoutePlan: Journey]` alongside the existing single `currentJourney` field. Rejected because it's two pieces of state that must stay in sync on every selection change — more bug surface for no benefit now that showing 3 routes is the default behavior, not an optional add-on to an existing single-route flow.

## Rendering (`MapView`)

- Draw one `MapPolyline` per `RouteOption` with a non-nil `journey`, colored by plan (green/yellow/red per above). The selected route draws with `lineWidth: 5`; the other two with `lineWidth: 3`.
- Start/End `Marker`s stay `.green` / `.red`, unchanged from today.
- A legend/chip row (`HStack` of 3 tappable chips: color dot + plan name), placed below the existing search bar. Tapping a chip sets `vm.selectedPlan`. A chip whose plan has no `journey` (failed request) renders dimmed with a warning glyph and is not tappable.

## Settings interaction

`MapView` reads `@AppStorage("defaultRoutePlan")` and passes the decoded `RoutePlan` as `MapViewModel`'s initial `selectedPlan` at construction (mirroring how `apiClient` is already passed in at init, per the DI convention in `docs/SPEC.md`).

## Scope boundary: `loadJourney(_:)`

`loadJourney(_:)` (populates the map from a reloaded saved route) stays single-journey: it populates `routeOptions` with exactly one `RouteOption` for that saved route's own `plan`, with no comparison fetch of the other two. Reloading a specific saved route by itinerary ID is a distinct flow from fresh planning; forcing 2 extra API calls there isn't part of this issue's ask and would add cost with no corresponding UI benefit (a saved route is already a specific, previously-chosen plan).

## Testing

- **`MockAPIClient.planJourney`** currently ignores the `plan` parameter (a single `journeyToReturn`/`shouldThrow` apply to every call regardless of plan) — needs extending with per-plan overrides (e.g. `journeysByPlan: [RoutePlan: Journey]`, `errorsByPlan: [RoutePlan: Error]`) so tests can express "quietest and balanced succeed, fastest fails."
- **New/updated `MapViewModelTests`:**
  - all 3 plans succeed → `routeOptions` has 3 entries with journeys, `currentJourney` matches `selectedPlan`
  - partial failure where the pre-selected plan fails → `selectedPlan` falls back to the first successful plan, `currentJourney` reflects the fallback
  - partial failure where a non-selected plan fails → `selectedPlan` unchanged, failed `RouteOption` has `errorMessage` set and `journey == nil`
  - all 3 fail → `currentJourney` is `nil`, all 3 `RouteOption`s carry `errorMessage`
  - selecting a different (successful) plan updates `currentJourney` accordingly
  - `MapViewModel` init reads the passed-in initial `selectedPlan` correctly (covers the `defaultRoutePlan` wiring fix)
- `MapView`'s new legend/chip row and marker recoloring are pure-SwiftUI-wiring — build-verify-only per `docs/SPEC.md` → Test coverage convention (no new logic beyond invoking `vm.selectedPlan = plan` on tap).

## Files touched

`Features/Map/MapViewModel.swift`, `Features/Map/MapView.swift`, `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`, `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`. `docs/SPEC.md` must be updated in the same commit (Map screen section, Settings section) per `CLAUDE.md`'s standing instruction.
