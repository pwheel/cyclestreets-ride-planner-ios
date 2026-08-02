# UAT Findings — Current Location search (GitHub #6, PR #15)

> Source plan: [`2026-08-01-current-location-search.md`](./2026-08-01-current-location-search.md)
> Source design: [`2026-07-26-current-location-search-design.md`](../specs/2026-07-26-current-location-search-design.md)
> Found via manual on-device/simulator walkthrough after PR #15 merged — the interactive pass neither the implementer subagents nor the controller could execute during development (no UI-automation tooling available; see GitHub #16, filed as a direct consequence of this gap).

**For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement these fixes. TDD where the fix has testable logic (`MapViewModel`/`LocationService`), build-verify-only where it's pure SwiftUI layout, matching the conventions established in the source plan.

---

## Finding 1: "Current Location" row renders oversized — takes up roughly half the screen

**Status:** 🔍 Open — root cause not yet confirmed visually (no UI-automation tooling available to this agent either — see GitHub #16).

**Severity:** Medium — the feature still works, but the dropdown looks broken/unpolished, which undermines trust in the row above it (the actual search results).

**Symptom (reported by user):** Tapping into the search field and looking at the dropdown, the "Current Location" row is "super-big" — takes up roughly half the screen, rather than reading as a compact single row above the search results.

**Root-cause hypothesis (from code, not yet visually confirmed):** `MapView.resultsList` (`CycleStreets Ride Planner/Features/Map/MapView.swift:417-468`) wraps the "Current Location" `Button` and the search-results `List` in a `VStack` with `.frame(maxHeight: 260)` applied to the *outer* `VStack`, not to the `List` itself:

```swift
private var resultsList: some View {
    VStack(alignment: .leading, spacing: 0) {
        Button { useCurrentLocation() } label: { ... }        // ~44-64pt intrinsic height
        if !vm.searchResults.isEmpty {
            Divider()
            List(vm.searchResults) { place in ... }            // no explicit height of its own
        }
    }
    .frame(maxHeight: 260)   // <- applied here, not on the List
    ...
}
```

This is a known SwiftUI pitfall: a `List` (backed by `UITableView`) is greedy — without its own explicit height, it expands to fill whatever space its container offers, regardless of how many rows it actually holds. Before this feature, the `List` had its own `.frame(maxHeight: 220)` directly on it (see the pre-feature version of this file); the current version dropped that in favor of the outer `VStack`'s `maxHeight: 260`, which the `List` then greedily consumes — pulling the *entire card* (button + divider + mostly-empty list) up toward 260pt tall even with very few or zero results, which could read as "the Current Location row is huge" if the empty/near-empty list space below it isn't visually distinguished from the row itself.

This exact risk was flagged as a Minor, deferred, not-visually-confirmed finding in this feature's own final code review (see PR #15's review notes) — this UAT finding is that risk materializing.

**Suggested fix:** Restore an explicit height constraint on the `List` itself (e.g. `.frame(maxHeight: 216)` on the `List`, matching roughly the old `220` minus the button+divider's own height, so the *total* card stays close to the previous ~260pt ceiling), rather than relying on the outer `VStack`'s `maxHeight` alone to constrain a greedy child. Needs to be re-checked visually once UI-automation tooling exists (GitHub #16) or via manual simulator confirmation.

**Files likely touched:** `Features/Map/MapView.swift`.

---

## Finding 2: First-time permission grant shows "Couldn't get your current location. Please try again," but retrying works

**Status:** 🔍 Open — root cause confirmed from code (high confidence), fix not yet applied.

**Severity:** High — this is the primary/first-run path for the entire feature. Every first-time user who grants permission hits a failure before the feature works, undermining trust regardless of the retry succeeding.

**Symptom (reported by user):** After tapping "Current Location" and selecting "Allow While Using App" on the system permission prompt, an error alert pops up: "Couldn't get your current location. Please try again." Tapping "Current Location" again immediately succeeds.

**Root cause:** `LocationService.currentLocation()` (`CycleStreets Ride Planner/Location/LocationService.swift:61-98`), when authorization is `.notDetermined`, awaits `requestAuthorization()` (`:100-112`), which races the real `CLLocationManagerDelegate` callback against a hardcoded 5-second timeout (`authorizationTimeout: Duration = .seconds(5)`, `:48`) added during PR #15's final review to fix a different bug (an unbounded wait when Location Services are off device-wide). If the timeout fires first — which is very plausible for a real human reading and deciding on the system permission dialog, especially the very first time — `resumeAuthorization(with: .notDetermined)` fires (`:108`), and `currentLocation()`'s switch statement (`:82-86`) maps a still-`.notDetermined` status to `throw LocationServiceError.unavailable`, which `MapViewModel.useCurrentLocation(as:)` surfaces as the generic "Couldn't get your current location. Please try again." error — even though the user's tap on "Allow While Using App" was already in flight or about to land.

The retry succeeds because by the second tap, `manager.authorizationStatus` is no longer `.notDetermined` (it's `.authorizedWhenInUse`), so the `if status == .notDetermined` branch — and therefore the 5-second race — is skipped entirely, going straight to a real location fetch.

**Suggested fix:** The 5-second ceiling is solving a real edge case (Location Services off device-wide, app status stuck `.notDetermined` forever) and shouldn't be removed outright, but 5 seconds is too aggressive for a human actually reading and responding to a system dialog. Options, roughly in order of preference:
1. Lengthen the timeout substantially (e.g. 30-60s) — a real "Location Services off device-wide" hang is rare and the user isn't otherwise blocked (the full-screen spinner is already showing), so a longer ceiling costs little in the genuine edge case while giving a real human enough time to respond in the common case.
2. Reset/restart the timeout whenever the app returns to the foreground (`UIApplication.didBecomeActiveNotification`) while the wait is pending, rather than using a single flat ceiling from the moment the prompt is requested — this would tolerate an arbitrarily slow human response as long as the app stays foregrounded, while still catching the "prompt never resolves at all" case (which manifests as the app never returning to a determined state even across foreground/background cycles).
3. At minimum, add a regression test asserting the specific failure mode from this finding: authorization resolves to `.authorizedWhenInUse` *after* the timeout fires (simulating a slow-but-real user response) still succeeds — this needs a `MockLocationService`-level test or a `LocationService`-specific test if one becomes feasible; currently `LocationService` is build-verify-only per this feature's test-coverage convention, so this may require loosening that if the fix can't otherwise be regression-tested.

**Files likely touched:** `Location/LocationService.swift`.

---

## Summary Table

| # | Finding | Type | Severity | Status |
|---|---|---|---|---|
| 1 | "Current Location" row renders oversized (greedy `List` sizing) | Bug (layout, unverified-at-review-time risk materializing) | Medium | 🔍 Open |
| 2 | False "couldn't get location" on first grant; 5s authorization timeout races a real human response | Bug (regression from PR #15's own final-review fix) | High | 🔍 Open |
