# Review Checklist

Run through this before considering any change complete — whether you're about to commit, open a PR, or hand back to the user. It's referenced from `AGENTS.md`; that's not optional context, it's how `docs/SPEC.md` stays trustworthy.

## 1. Tests

- [ ] New behavior/bugfix was written test-first (RED confirmed for the right reason, then GREEN) — see the project's TDD conventions.
- [ ] Full suite run (not just the targeted test), and confirmed green from actual output — not assumed from a build success alone.
- [ ] If a mock (`MockAPIClient`, etc.) was touched, check it still faithfully simulates the real implementation's behavior (e.g. cancellation, error types) — a mock that's too permissive hides real bugs. This exact gap caused a shipped regression once; see `docs/superpowers/plans/2026-07-19-uat-findings-v1.md` Finding 5.

## 2. Spec accuracy — `docs/SPEC.md`

Ask: did this change do any of the following? If yes, update the relevant section of `docs/SPEC.md` **in the same commit**.

- [ ] Added, removed, or renamed a screen, View, or ViewModel
- [ ] Changed a public ViewModel method's signature or behavior (what it does, when it sets error state, what triggers it)
- [ ] Added, removed, or changed a CycleStreets API endpoint call, request shape, or response decoding
- [ ] Changed the persistence schema (fields on `SavedRoute`/`SavedLocation`, or how/where data is stored)
- [ ] Introduced or changed a cross-cutting pattern worth reusing elsewhere (e.g. the cross-tab hand-off pattern)
- [ ] Closed a gap in "Known limitations / roadmap" or "Test coverage" gaps listed in SPEC.md

If none of the above apply, no SPEC.md change is needed — say so explicitly rather than skipping the check silently.

## 3. Historical record — `docs/superpowers/plans/`

- [ ] If this change fixes a tracked UAT finding, update its status/commit SHA in `2026-07-19-uat-findings-v1.md`.
- [ ] If this change surfaces new descoped/future work, capture it on the roadmap doc rather than letting it evaporate.

## 4. Secrets

- [ ] `git diff`/`git status` doesn't introduce a real API key, token, or credential. `Resources/APIKey_dev.txt` must stay `skip-worktree`-flagged — don't `git add -f` it or remove the flag.

## 5. Commit hygiene

- [ ] Commit message explains *why*, not just *what* (the diff already shows what).
- [ ] No unrelated changes bundled in (e.g. local Xcode signing config in `project.pbxproj` — check before staging).
