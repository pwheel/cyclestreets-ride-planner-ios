# GitHub Actions CI — design

Closes: https://github.com/pwheel/cyclestreets-ride-planner-ios/issues/5

## Goal

Run the existing test suite automatically on every PR and every push to `main`, using a hosted macOS runner, so regressions are caught before merge without any manual `xcodebuild test` step.

## Runner & Xcode/simulator match

The project targets `IPHONEOS_DEPLOYMENT_TARGET = 26.5` and local dev pins the simulator to `iPhone 17` (per `CLAUDE.md`). Checked against `actions/runner-images`: the `macos-26` image's **default** Xcode is 26.5 (build 17F42), and its iOS 26.5 simulator runtime includes `iPhone 17` — an exact match to local dev, no extra SDK/simulator installation needed.

`runs-on: macos-26` is pinned explicitly rather than `macos-latest` (which will eventually move past 26 as new OS images ship) or `macos-26-large`/`-xlarge` (paid tiers, unnecessary here). Pinning avoids a future runner migration silently changing the default Xcode/simulator out from under this workflow.

## Workflow

New file: `.github/workflows/test.yml`

- **Triggers:** `pull_request` (any branch) and `push` to `main`.
- **Concurrency:** grouped per-ref with `cancel-in-progress: true`, so a superseded push/PR update doesn't leave a stale run queued.
- **Job:** single job, `runs-on: macos-26`, `timeout-minutes: 30` (normal run is a few minutes; generous headroom for the multiple simulator-clone spin-up `xcodebuild test` does, per `CLAUDE.md`'s note that this is normal, not a hang).
- **Steps:**
  1. `actions/checkout@v4`
  2. Confirm/select Xcode 26.5 (`xcode-select -p`; fall back to explicit `sudo xcode-select -s /Applications/Xcode_26.5.app` only if the probe shows a different default — keeps the workflow resilient if the image's default Xcode version changes before this is revisited)
  3. Run the suite, skipping the UI test target:
     ```
     xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skip-testing:"CycleStreets Ride PlannerUITests"
     ```
     **Revised from the original design** (which ran the full suite with no `-only-testing`/`-skip-testing` filter): a real CI run showed `CycleStreets Ride PlannerUITests-Runner` failing to initialize with "Timed out while loading Accessibility" — a known GitHub Actions macOS-runner limitation for XCUITest, not an app defect. Since the target is currently just Xcode's default launch/screenshot boilerplate (already outside `docs/SPEC.md`'s test-coverage list), skipping it in CI was the pragmatic choice; local dev can still run it manually.

     The same CI run also showed `MapViewModelTests.testSearchTextChangedDebouncesAndSearches()` and `testSearchTextChangedCancelsPendingSearchOnRapidTyping()` failing intermittently — both use real wall-clock `Task.sleep` with thin margins relative to their configured debounce duration, which flaked under CI's slower/shared-vCPU scheduling despite passing reliably locally. An initial fix widened the sleep margins, but that only reduced the flake rate rather than eliminating it, since it was still a fixed-duration guess at how long the async work would take. Root-caused and fixed instead in commit `9bdeb18` by replacing the trailing "wait for async completion" sleeps in four tests with a `waitUntil` helper that polls the relevant condition (5s timeout, 10ms interval) until it's true, deterministic regardless of scheduling delay. The short mid-debounce gap sleeps that test genuine relative-timing behavior (keystroke arrives before vs. after the debounce window) are left as fixed sleeps, since that ordering is what's under test.

## Secrets / API key

No secrets configuration needed. `APIKey_dev.txt` is committed to git with a placeholder value (`skip-worktree` only affects the local working tree's edit-tracking, not what a fresh `git checkout` produces in CI). This is sufficient to compile and run unit tests, which use `MockAPIClient` and don't hit the live API. The UI test target's boilerplate launch test also doesn't require live network access.

## Out of scope (not requested, no existing precedent in the project)

- Code signing / archiving
- Uploading test results, screenshots, or `.xcresult` as artifacts
- A build matrix across multiple simulators/OS versions
- Lint steps (SwiftLint etc.)
- A CI status badge in the README

## Files touched

- New: `.github/workflows/test.yml`
