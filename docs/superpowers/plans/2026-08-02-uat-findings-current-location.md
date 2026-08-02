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

## Finding 3: "Current Location" still offered for the second waypoint after already being used for the first

**Status:** ✅ Fixed — commit `179320b`.

**Severity:** Low-Medium — usability papercut, not a functional bug (nothing crashes or plans a nonsensical route unless the user actually taps it), but the reported effect — "makes it look to the user like nothing has happened" — undermines confidence in the whole feature right after its first successful use.

**Symptom (reported by user):** After selecting "Current Location" for the `From` field, the dropdown for the `To` field still offers "Current Location". Selecting it there doesn't make sense (routing from your current location to your current location), and because the picker's flip from "From" to "To" after the first selection is visually subtle, a user tapping "Current Location" again can read the whole interaction as having done nothing.

**Root cause:** `MapView.resultsList`'s "Current Location" row was shown unconditionally whenever the search field was focused, with no awareness of whether the *other* waypoint (`vm.fromPlace`/`vm.toPlace`, whichever `selectingFor` isn't currently pointing at) was already set to a Current Location place.

**Fix:** Added `Place.currentLocationName` (a shared constant, replacing the duplicated `"Current Location"` string literal in `MapViewModel.useCurrentLocation`) and a computed `Place.isCurrentLocation`. `MapView` gained `otherWaypointIsCurrentLocation`, checking whichever waypoint `selectingFor` is *not* about to fill, and the row is now hidden whenever that's true (folded into the same `isShowingCurrentLocationRow` gate as Finding 4, since both conditions govern the same row).

**Files touched:** `Models/Place.swift`, `Features/Map/MapViewModel.swift`, `Features/Map/MapView.swift`.

---

## Finding 4: "Current Location" stays in the dropdown after the user starts typing

**Status:** ✅ Fixed — commit `179320b`.

**Severity:** Low-Medium — same class of issue as Finding 3: not a functional bug, but a preset row sitting above live search results the user is actively typing past doesn't read as intentional.

**Symptom (reported by user):** Once the user starts typing in the search field, "Current Location" remains visible in the dropdown even though the user is clearly searching by name at that point and isn't going to tap it.

**Root cause:** Same as Finding 3 — the row's visibility was gated only on `isSearchFieldFocused`, with no consideration of `searchText`.

**Fix:** Folded into the same `isShowingCurrentLocationRow` computed property as Finding 3: `searchText.isEmpty && !otherWaypointIsCurrentLocation`. Per the user's stated future direction — a "Saved Locations" preset row is planned to sit alongside "Current Location" in this same dropdown, and both should disappear the same way once typing starts — `isShowingCurrentLocationRow`'s doc comment flags this as the pattern any future preset row should follow, rather than building that abstraction now.

Also fixed as part of this same change: when the row is hidden by either Finding 3 or 4's condition *and* there are no search results, `resultsList` previously would have rendered as an empty floating rounded-rect card (no button, no list, just the background/padding). Added `resultsListIsEmpty` so the whole card is omitted in that state instead.

**Files touched:** `Features/Map/MapView.swift`.

---

## Finding 5: Typing in the `To` search field once showed "The data couldn't be read because it is missing"

**Status:** 🔍 Monitoring — not reliably reproducible. Not fixed, and no fix has been guessed at; captured so it isn't lost if it recurs.

**Severity:** Unknown — reported once, severity depends entirely on how often it actually happens, which isn't established yet.

**Symptom (reported by user):** After selecting "Current Location" for the `From` field, typing in the `To` field produced an error alert: "The data couldn't be read because it is missing." On a later attempt, the user could not reproduce it.

**Investigation:** Ruled out the one thing this exact message is best-known to indicate in this codebase — a placeholder/missing API key (`CLAUDE.md`'s documented new-worktree gotcha produces this identical generic-decode-error text). Both `Resources/APIKey_dev.txt` and `Resources/ThunderforestAPIKey_dev.txt` were confirmed to hold real values, not placeholders, at the time of investigation. Attempted to reproduce live via simulator UI automation (select Current Location for `From`, then type in `To`) on a freshly rebuilt/reinstalled app — no error occurred, though that specific attempt is inconclusive since the synthetic keystroke didn't actually land text in the field (the search field still showed its placeholder afterward), so it wasn't a valid test of the typing path either way.

**Leading hypothesis (unconfirmed):** "The data couldn't be read because it is missing" is Foundation's generic `localizedDescription` for a `JSONDecoder` failure — i.e. `GeocoderDecoder` received a response that didn't match the expected shape. The most plausible trigger for a one-off, non-reproducible instance of this is a transient network hiccup (iOS Simulators are known to have a brief network-stack warm-up glitch immediately after boot) or a transient CycleStreets API blip, rather than a deterministic bug in this session's changes — nothing in the Current Location work touches `search(query:)`/`GeocoderDecoder`/the "To"-field code path differently from "From." Not confirmed; no code changes were made against this hypothesis, since guessing at a fix for an unreproducible symptom risks solving the wrong problem.

**Separate, lower-priority observation surfaced by this investigation (not a fix for this finding):** whatever the root cause turns out to be, `MapViewModel.search(query:)`'s catch-all (`errorMessage = error.localizedDescription`) will surface *any* decode/network failure using Foundation's raw, often-unhelpful default message. Worth considering a friendlier, more actionable geocode-failure message generally — but that's a pre-existing quality gap unrelated to this feature, not something to fix under this finding.

**Next step if it recurs:** capture the device log at the moment it happens (`xcrun simctl spawn <device> log show --predicate 'process == "CycleStreets Ride Planner"' --last 2m`) to see the actual underlying `URLError`/`DecodingError` rather than the generic UI string, which is the missing piece that would turn this from a hypothesis into a confirmed root cause.

**Files:** none touched — no fix applied.

---

## Summary Table

| # | Finding | Type | Severity | Status |
|---|---|---|---|---|
| 1 | "Current Location" row renders oversized (outer VStack's own maxHeight, not just a greedy List) | Bug (layout, unverified-at-review-time risk materializing) | Medium | ✅ Fixed |
| 2 | False "couldn't get location" on first grant; 5s authorization timeout races a real human response | Bug (regression from PR #15's own final-review fix) | High | ✅ Fixed |
| 3 | "Current Location" still offered for the second waypoint after already used for the first | Usability | Low-Medium | ✅ Fixed |
| 4 | "Current Location" stays visible in the dropdown once the user starts typing | Usability | Low-Medium | ✅ Fixed |
| 5 | One-off "data couldn't be read" error typing in `To`; not reproducible on retry | Bug (unconfirmed — possibly transient network/simulator glitch) | Unknown | 🔍 Monitoring |

Findings 1-2 were confirmed and fixed with genuine simulator UI automation (Accessibility + Screen Recording permissions granted mid-session), not code inspection alone — the exact capability gap tracked in GitHub #16, closed just enough for this session to verify its own fixes. Findings 3-4 are pure SwiftUI visibility-condition changes, build-verify-only per this project's test-coverage convention for view layout.
