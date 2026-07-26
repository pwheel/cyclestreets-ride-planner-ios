# GitHub Actions CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that runs the full `xcodebuild test` suite on every PR and every push to `main`, closing issue #5.

**Architecture:** A single new workflow file, `.github/workflows/test.yml`, with one job on a pinned `macos-26` runner. No app code changes — this is CI/tooling only, and the actual pass/fail signal comes from GitHub Actions itself running against a real push, not from a local test.

**Tech Stack:** GitHub Actions YAML, `xcodebuild`, GitHub's `macos-26` hosted runner image (Xcode 26.5 default, iOS 26.5 simulator).

## Global Constraints

(From `docs/superpowers/specs/2026-07-26-github-actions-ci-design.md` — copied verbatim, every task's requirements implicitly include these.)

- Runner: `macos-26`, pinned explicitly — not `macos-latest` or `macos-26-large`/`-xlarge`.
- Triggers: `pull_request` (any branch) and `push` to `main`.
- Concurrency: grouped per-ref, `cancel-in-progress: true`.
- Job timeout: `timeout-minutes: 30`.
- Test command run verbatim, no `-only-testing` filter (both unit and UI test targets run):
  ```
  xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17"
  ```
- Xcode selection: probe the runner's default via `xcode-select -p`; only force-select `/Applications/Xcode_26.5.app` if the default isn't already Xcode 26.5.
- No secrets/API key configuration — `APIKey_dev.txt`'s committed placeholder value is sufficient.
- Out of scope: code signing, artifact upload, build matrix, linting, README badge.

---

## Task 1: Create and validate the workflow file

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:** None — this is the only file in the plan.

- [ ] **Step 1: Create the workflow file**

Write `.github/workflows/test.yml` with this exact content:

```yaml
name: Test

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Ensure Xcode 26.5 is selected
        run: |
          current=$(xcode-select -p)
          echo "Default Xcode developer dir: $current"
          if [[ "$current" != *"Xcode_26.5"* ]]; then
            echo "Switching to Xcode 26.5"
            sudo xcode-select -s /Applications/Xcode_26.5.app
          fi
          xcodebuild -version

      - name: Run test suite
        run: |
          xcodebuild test \
            -project "CycleStreets Ride Planner.xcodeproj" \
            -scheme "CycleStreets Ride Planner" \
            -destination "platform=iOS Simulator,name=iPhone 17"
```

- [ ] **Step 2: Validate YAML syntax locally**

Run: `ruby -ryaml -e "YAML.load_file('.github/workflows/test.yml'); puts 'valid'"`
Expected: `valid` printed, no exception.

(Optional, best-effort — skip if not installed, don't install it as part of this task): if `actionlint` is on `PATH`, also run `actionlint .github/workflows/test.yml` and expect no output.

- [ ] **Step 3: Confirm no other project docs need updating**

Per `docs/REVIEW_CHECKLIST.md` §2, this change doesn't add/remove/change a screen, ViewModel, API endpoint, or persistence schema — so `docs/SPEC.md` needs no update. Note this explicitly in the commit message rather than skipping the check silently.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "$(cat <<'EOF'
ci: add GitHub Actions workflow to build and run tests

Runs the full xcodebuild test suite (unit + UI targets) on every PR
and push to main, on macos-26 — matches local dev's Xcode 26.5 /
iPhone 17 simulator exactly. No docs/SPEC.md change needed: CI/tooling
only, no screen/ViewModel/API/persistence change.

Closes #5
EOF
)"
```

---

## Task 2: Verify the workflow actually runs green on GitHub Actions

Local YAML validation (Task 1) only catches syntax errors — it cannot confirm the job boots the runner, resolves the simulator, or that `xcodebuild` actually passes in that environment. This task is the real functional test, and it requires pushing to the shared remote repo.

**CHECKPOINT — before Step 1:** pushing a branch and opening a PR are visible, shared-state actions. Confirm with the user before proceeding, even though this plan was written with that expectation.

**Files:** None (verification only).

- [ ] **Step 1: Push the branch**

```bash
git push -u origin worktree-issue-5-github-actions-ci
```

Expected: push succeeds, prints the new remote branch ref.

- [ ] **Step 2: Open a PR to trigger the `pull_request` event**

```bash
gh pr create --repo pwheel/cyclestreets-ride-planner-ios \
  --title "ci: add GitHub Actions workflow to build and run tests" \
  --body "$(cat <<'EOF'
## Summary
- Adds `.github/workflows/test.yml`: runs the full `xcodebuild test` suite (unit + UI) on PRs and pushes to `main`, on `macos-26` (Xcode 26.5 / iPhone 17 simulator — matches local dev).

Closes #5

## Test plan
- [ ] Workflow run on this PR itself is green
EOF
)"
```

Expected: PR URL printed.

- [ ] **Step 3: Watch the triggered run**

```bash
gh pr checks --repo pwheel/cyclestreets-ride-planner-ios --watch
```

Expected: the `Test` check transitions to `pass`. If it fails, read the run log (`gh run view --log-failed`) to determine whether it's a genuine workflow bug (fix and repeat from Task 1 Step 4) or an environment mismatch (e.g. `iPhone 17` not present on the runner despite the README — re-check `actions/runner-images` docs for the current image and adjust the `-destination` value).

- [ ] **Step 4: Report result to the user**

Summarize: PR link, run status, and total run time (useful for sanity-checking the 30-minute timeout).

---

## Self-Review

**Spec coverage:** Runner pin ✓ (Task 1 Step 1), triggers ✓, concurrency ✓, timeout ✓, exact test command ✓, conditional Xcode selection ✓, no-secrets rationale ✓ (design already established, nothing to configure), SPEC.md decision recorded ✓ (Task 1 Step 3), out-of-scope items excluded (no signing/artifacts/matrix/lint/badge added) ✓, real-environment verification ✓ (Task 2 — the design's runner/simulator match is a documentation claim until a real run confirms it).

**Placeholder scan:** No TBD/TODO; every step has literal file content or literal commands with stated expected output.

**Type consistency:** N/A — no code symbols across tasks (YAML + shell only).
