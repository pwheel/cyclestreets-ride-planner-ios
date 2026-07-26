# Agent Instructions — CycleStreets Ride Planner (iOS)

SwiftUI/MVVM iOS app for planning cycle routes via the CycleStreets API, with local persistence for saved routes/locations. No user accounts.

**Read `docs/SPEC.md` first** for architecture, screens, the API contract, and current known limitations. This file is operational instructions only.

## Build & test

```
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17"
```

- The simulator must be named exactly `iPhone 17` on this machine (`iPhone 16` isn't available) — check `xcrun simctl list devices` if the destination fails and adjust.
- **Stale incremental build gotcha:** `xcodebuild` has been observed to silently skip recompiling a changed test file, causing a rerun to report the *old* pass/fail state. If a newly-added test doesn't appear in the output, or a bug you just fixed still fails identically, compare the `.xctest` bundle's mtime (under `DerivedData/.../Products/Debug-iphonesimulator/*.app/PlugIns/*.xctest`) against your source file's mtime. If the bundle is older, `touch` the changed file(s) and rerun.
- Full-suite runs spin up 2–3 simulator "clones" for parallel testing — this is normal `xcodebuild` behavior, not a hang. Don't manually close/kill clones; let `xcodebuild` manage them.
- Be mindful of system resource load on heavy `xcodebuild` runs. Don't aggressively retry a cancelled or failed run in a tight loop if the failure looks resource-related (e.g. "Invalid device state", Mach IPC errors) rather than a genuine code error — one retry is fine, repeated rapid retries can compound an already-strained machine.

## Conventions

- **Swift Testing**, not XCTest: `import Testing`, `@Test func ...`, `#expect(...)`.
- **TDD**: write a failing test, confirm it fails for the right reason, implement minimally, confirm green. Pure-SwiftUI-wiring changes with no testable logic (navigation, `@State` resets) are build-verify-only — see `docs/SPEC.md` → Test coverage for the established list of what falls in that bucket.
- **Xcode 16+ `PBXFileSystemSynchronizedRootGroup`**: new source files placed under a synced folder are auto-included in the target. Don't hand-edit `project.pbxproj` to add/remove source files.
- `@Observable @MainActor final class` for ViewModels; plain `Codable, Equatable` structs/enums for models.
- Cross-tab state hand-off: see `docs/SPEC.md` → "Cross-tab hand-off pattern" before inventing a new mechanism for passing state/actions between tabs.

## Secrets

- Real API key: `CycleStreets Ride Planner/Resources/APIKey_dev.txt`, protected via `git update-index --skip-worktree` — not `.gitignore`. Never `git add -f` it or drop the skip-worktree flag.
- `APIKey_live.txt` is gitignored outright, used for release builds only.

## Branching

Never commit directly to `main`. Use at least a branch for minor work (docs-only tweaks, one-line fixes); prefer a git worktree for everything else, so the change is isolated from whatever else is checked out in the primary working directory.

## Before finishing any change

Work through `docs/REVIEW_CHECKLIST.md`. In particular: **`docs/SPEC.md` must be updated in the same commit** as any change that adds/removes/materially changes a screen, ViewModel contract, API endpoint, persistence schema, or cross-cutting pattern. This is not optional — an out-of-date spec is worse than no spec, because future agents will trust it.
