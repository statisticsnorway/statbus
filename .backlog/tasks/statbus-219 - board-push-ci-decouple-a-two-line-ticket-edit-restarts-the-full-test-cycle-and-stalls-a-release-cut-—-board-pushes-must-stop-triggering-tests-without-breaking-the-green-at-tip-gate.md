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
updated_date: '2026-08-18 08:20'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-18 08:19
---
DESIGN RULED — doc-030 (board-push-ci-decouple: design ruling for STATBUS-219). Two stages, deliberately separable. Three findings, all verified at writing time.

FINDING 1 — IMAGES IS NOT A TEST GATE AND CAN NEVER RIDE. The other four preflight gates ask "did this content pass?"; images asks "does ghcr.io/...:<commit_short> EXIST?". No argument about markdown makes an image materialise at a SHA nothing published to. The codebase already says the consequence out loud in the SKIP_IMAGES bypass text (workflow_check.go:104-107: "Deployments may FAIL on stale ghcr.io manifest"), and fast-tests proves the coupling — on the chained path it PULLS the commit_short-tagged images and statbus-seed:<commit_short> rather than building (fast-tests.yaml:139-142, :164-165). Images is excluded from every exemption mechanism, permanently, reason recorded in code.

FINDING 2 — THE NAIVE TRIGGER FIX IS WORSE THAN THE TICKET STATES. A paths-ignore on images.yaml does not only leave the preflight with no run at the tip (the trap the ticket names); it ALSO skips the chained pg_regress and fast-tests (workflow_run off Images — pg_regress.yaml:4-6, fast-tests.yaml:39-41) AND leaves the commit with no Docker images at all. A release cut there would be undeployable.

FINDING 3 — THE STALL IS FULLY CURABLE PREFLIGHT-SIDE ALONE. The observed refusal was "fast-tests is still PENDING", which means Images had already completed green at the tip (fast-tests only exists because Images finished). The cut was not waiting on a MISSING run — it was waiting on a REDUNDANT one. So the ride alone cures the King's pain, with no trigger change, no artifact risk, and no unverified premise.

STAGE 1 (ratify and build now, preflight only): checked-in ops/release/ci-exempt-paths.txt, starting at exactly one entry, `.backlog/`. When a VERDICT gate is not green at the tip — Missing or Pending or Failed — walk first-parent ancestors nearest-first, bounded 50, computing the DIRECT `git diff --name-only C..tip` per candidate (never per-hop induction — same correct-by-construction reasoning checkUpgradeArcHarnessGate documents, and strictly more capable: an add-then-revert pair yields an empty direct diff and rides soundly). First exempt-clean green ancestor is the ride target. Non-exempt diff, exhausted walk, or no green ancestor all refuse exactly as today. Output is loud: ride SHA, commits ridden, every justifying file.

THE ONE DESIGN POINT THE BUILDER MOST LIKELY GETS WRONG — THE MATCHING RULE INVERTS. diffTouchesSensitivePath (release.go:1322) uses SUBSTRING containment because for a SENSITIVITY list over-inclusive is the safe direction (a coincidental hit costs one extra run). For an EXEMPT list the failure directions mirror: over-inclusive means more commits treated as needing no tests, i.e. untested code waved into a release. Exempt matching must be UNDER-inclusive — anchored path prefix. DO NOT reuse diffTouchesSensitivePath; write a separate helper whose comment states the inversion so nobody copies the wrong conservatism forward.

STAGE 2 (shape ruled, BUILD GATED ON A PROBE): images.yaml decides internally — exempt-only pushes take a RETAG path (copy the parent's manifests to the new SHA, seconds) instead of a skip, so the invariant "every master commit has images at its SHA" holds unconditionally and NOTHING downstream (deployment, upgrade, arcs, install) changes. The chained pair is the hard part and must not self-report: workflow_run fires regardless, so pg_regress/fast-tests will start, and everything turns on what GitHub concludes for an all-jobs-skipped run. `success` = a phantom green, the exact 199/215 softness, and it would hide the ride from the operator. `skipped` = harmless, since CheckWorkflowAtCommit treats non-success as not-green (workflow_check.go:94) and Stage 1's ride then decides explicitly and loudly. WE DO NOT KNOW WHICH, and our one local data point (run 32009980725 concluded SUCCESS with the arc matrix skipped) does not settle it — other jobs in that run did execute. PROBE IT before building Stage 2, one-shot scratch branch, same method that settled 215. If `success`, Stage 2 shrinks to the independent triggers (go-test, app-build-lint) plus the images retag, and the chained pair keeps running redundantly — which Stage 1 has already made harmless.

SCOPE NOTE ON THE EXEMPT LIST: `doc/` is the obvious next candidate and is probably safe (its only known gate, .claude/hooks/doc-db-freshness.sh, is a local commit hook, not a CI input), but it ships as its own argued addition rather than riding in on this one. AC#5 is enforced mechanically, not remembered: a test asserts ci-exempt-paths.txt does not match any entry in its own list, so changing what counts as test-irrelevant can never ride a prior green.
---

author: foreman
created: 2026-08-18 08:20
---
SEQUENCING (foreman): Stage 1 (preflight-side ride, release.go + ops/release/ci-exempt-paths.txt + tests) is assigned to the ENGINEER as his next unit AFTER the 216/217/218 gate-hardening round lands — same file (release.go), same owner, no parallel editing. His brief will carry the architect's matching-rule warning VERBATIM: the exempt list's matching must be under-inclusive (anchored path prefix), the inverse of diffTouchesSensitivePath's substring containment, in a separate helper whose comment states the inversion. Stage 2's all-jobs-skipped conclusion probe runs after the round lands and the tree is clean (scratch-branch method, same as the 215 probe); Stage 2 build gated on that result per the design. Images is excluded from every exemption permanently — it is a publish step, not a verdict; content-identical does not mean artifact-present.
---
<!-- COMMENTS:END -->
