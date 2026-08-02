# UAT Findings — Current Location search (GitHub #6, PR #15)

> Source plan: [`2026-08-01-current-location-search.md`](./2026-08-01-current-location-search.md)
> Source design: [`2026-07-26-current-location-search-design.md`](../specs/2026-07-26-current-location-search-design.md)
> Found via manual on-device/simulator walkthrough after PR #15 merged — the interactive pass neither the implementer subagents nor the controller could execute during development (no UI-automation tooling available; see GitHub #16, filed as a direct consequence of this gap).

**For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement these fixes. TDD where the fix has testable logic (`MapViewModel`/`LocationService`), build-verify-only where it's pure SwiftUI layout, matching the conventions established in the source plan.

---

## Finding 1: "Current Location" row renders oversized — takes up roughly half the screen

**Status:** ✅ Fixed — commit `6899887`. Confirmed visually via simulator UI automation (accessibility + screen recording permissions granted mid-session — see below), not just inferred from code.

**Severity:** Medium — the feature still works, but the dropdown looks broken/unpolished, which undermines trust in the row above it (the actual search results).

**Symptom (reported by user):** Tapping into the search field and looking at the dropdown, the "Current Location" row is "super-big" — takes up roughly half the screen, rather than reading as a compact single row above the search results.

**Root cause (confirmed empirically via simulator UI automation, not just code reading):** `MapView.resultsList` wrapped the "Current Location" `Button` and the search-results `List` in a `VStack` with `.frame(maxHeight: 260)` applied to the *outer* `VStack`. The initial code-only hypothesis was that a greedy `List` was the culprit (a known SwiftUI pitfall: `List` expands to fill whatever space it's offered, regardless of row count) — but a screenshot taken with the search field focused and *zero* search results (so no `List` in the hierarchy at all — just the one `Button`) still showed the oversized card, disproving that as the sole cause. The actual behavior: inside this view's `ZStack` (a sibling `.ignoresSafeArea` map offers effectively unbounded height), a plain `VStack` with an outer `maxHeight` cap expanded to fill that cap even with a single small child. The `List`'s own greediness is a real secondary risk once results *do* appear, but the primary bug was the outer frame itself.

This exact risk was flagged as a Minor, deferred, not-visually-confirmed finding in this feature's own final code review (see PR #15's review notes) — this UAT finding is that risk materializing, and more severe than the reviewer's hypothesis anticipated.

**Fix:** Removed `.frame(maxHeight: 260)` from the outer `VStack` entirely. Added `.frame(maxHeight: 200)` directly on the `List` instead (the only genuinely greedy element), matching this view's pre-feature behavior (the `List` always had its own explicit height cap). Verified visually: the row now renders as a compact ~64pt tall control, matching normal search-result-row sizing, in both the zero-results and populated-results states.

**Files touched:** `Features/Map/MapView.swift`.

---

## Finding 2: First-time permission grant shows "Couldn't get your current location. Please try again," but retrying works

**Status:** ✅ Fixed — commit `6899887`. Confirmed via simulator UI automation: reset the app's location permission to not-determined, triggered the real system "Allow While Using App?" prompt, waited for a real (human, not scripted) response, and the flow completed successfully with no error — device log confirmed zero occurrences of the error string, no faults/crashes.

**Severity:** High — this is the primary/first-run path for the entire feature. Every first-time user who grants permission hits a failure before the feature works, undermining trust regardless of the retry succeeding.

**Symptom (reported by user):** After tapping "Current Location" and selecting "Allow While Using App" on the system permission prompt, an error alert pops up: "Couldn't get your current location. Please try again." Tapping "Current Location" again immediately succeeds.

**Root cause:** `LocationService.currentLocation()` (`CycleStreets Ride Planner/Location/LocationService.swift:61-98`), when authorization is `.notDetermined`, awaits `requestAuthorization()` (`:100-112`), which races the real `CLLocationManagerDelegate` callback against a hardcoded 5-second timeout (`authorizationTimeout: Duration = .seconds(5)`, `:48`) added during PR #15's final review to fix a different bug (an unbounded wait when Location Services are off device-wide). If the timeout fires first — which is very plausible for a real human reading and deciding on the system permission dialog, especially the very first time — `resumeAuthorization(with: .notDetermined)` fires (`:108`), and `currentLocation()`'s switch statement (`:82-86`) maps a still-`.notDetermined` status to `throw LocationServiceError.unavailable`, which `MapViewModel.useCurrentLocation(as:)` surfaces as the generic "Couldn't get your current location. Please try again." error — even though the user's tap on "Allow While Using App" was already in flight or about to land.

The retry succeeds because by the second tap, `manager.authorizationStatus` is no longer `.notDetermined` (it's `.authorizedWhenInUse`), so the `if status == .notDetermined` branch — and therefore the 5-second race — is skipped entirely, going straight to a real location fetch.

**Fix:** Lengthened `authorizationTimeout` from 5 seconds to 60 seconds. The genuine edge case it guards against (Location Services off device-wide, app status stuck `.notDetermined` forever) is rare, and the full-screen spinner already showing means a long wait costs little in that rare case — so bias heavily toward tolerating a slow human over firing early. `LocationService` remains build-verify-only per this feature's established test-coverage convention (no `CLLocationManager` abstraction exists to unit-test the race itself); this fix was verified via simulator UI automation instead (see Status above) rather than an automated regression test.

**Files touched:** `Location/LocationService.swift`.

---

## Summary Table

| # | Finding | Type | Severity | Status |
|---|---|---|---|---|
| 1 | "Current Location" row renders oversized (outer VStack's own maxHeight, not just a greedy List) | Bug (layout, unverified-at-review-time risk materializing) | Medium | ✅ Fixed |
| 2 | False "couldn't get location" on first grant; 5s authorization timeout races a real human response | Bug (regression from PR #15's own final-review fix) | High | ✅ Fixed |

Both findings were confirmed and fixed with genuine simulator UI automation (Accessibility + Screen Recording permissions granted mid-session), not code inspection alone — the exact capability gap tracked in GitHub #16, closed just enough for this session to verify its own fixes.
