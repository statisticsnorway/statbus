---
id: STATBUS-219
title: >-
  board-push-ci-decouple: a two-line ticket edit restarts the full test cycle
  and stalls a release cut — board pushes must stop triggering tests, without
  breaking the green-at-tip gate
status: To Do
assignee:
  - architect
created_date: '2026-08-18 08:13'
labels:
  - ci
  - release
  - backlog-workflow
dependencies: []
references:
  - .github/workflows/images.yaml
  - .github/workflows/pg_regress.yaml
  - cli/cmd/release.go
priority: medium
type: enhancement
ordinal: 219000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: every push to master fires the Images workflow, and pg_regress plus Fast Tests chain off it (workflow_run on Images completed). The release preflight then demands each of these oracles green AT THE EXACT TIP COMMIT before a cut. Together they guarantee no release is tagged on untested code.

WHAT GOES WRONG: the trigger has no notion of what changed. The team's board lives in the repo (.backlog/), so a two-line ticket comment restarts the entire commit-scope test cycle — and because the preflight keys on the tip, a cut arriving minutes later waits 10-15 minutes for tests that a markdown edit made necessary. Observed live 2026-08-18: the v2026.08.0-rc.03 cut was refused with "fast-tests is still pending" at bafcb396b, a commit that changed two lines of ticket text. The King ruled: board commits triggering fast tests is nonsensical.

THE DETAIL: the naive fix — a paths-ignore for .backlog/** on the Images trigger — breaks the other half of the contract. The preflight (cli/cmd/release.go) looks for a green run AT the tip SHA; if Images skips a board-only push, the next cut finds NO run at the tip and refuses outright. We would trade a 15-minute wait for a hard stop. Trigger and gate must move together.

THE FIX (design needed — architect): let the preflight accept a green run at the nearest ancestor commit when every commit between that ancestor and the tip touches only exempt paths (.backlog/, and any other doc-only sets the architect rules exempt), with the exempt-path list checked in and itself treated as sensitive — changing what counts as "doesn't need tests" must be a visible, gated act (same doctrine as ops/release/upgrade-sensitive-paths.txt being on its own sensitivity list). The trigger side can then skip exempt-only pushes outright.

WHY THAT HELPS: board activity — the team's normal coordination — stops competing with releases for CI time and stops delaying cuts, while the guarantee stays exact: every release still sits on a commit whose code content is fully tested, because only provably test-irrelevant commits may ride an ancestor's green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect design ratified: the exempt-path mechanism, its checked-in list, and the ancestor-walk rule in the preflight
- [ ] #2 A board-only push does not run Images/pg_regress/Fast Tests (or runs a skip that costs seconds, per the ratified design)
- [ ] #3 A cut on a tip whose only diff vs the last tested commit is exempt paths passes preflight using the ancestor's green runs
- [ ] #4 A cut on a tip containing ANY non-exempt change still refuses without a green run at that code state
- [ ] #5 The exempt-path list is itself sensitive: changing it cannot ride a prior green
<!-- AC:END -->
