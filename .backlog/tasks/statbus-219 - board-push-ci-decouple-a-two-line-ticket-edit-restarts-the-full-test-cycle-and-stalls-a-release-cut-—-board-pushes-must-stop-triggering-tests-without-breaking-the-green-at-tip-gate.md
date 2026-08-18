---
id: STATBUS-219
title: >-
  board-push-ci-decouple: a two-line ticket edit restarts the full test cycle
  and stalls a release cut — board pushes must stop triggering tests, without
  breaking the green-at-tip gate
status: In Progress
assignee:
  - engineer
created_date: '2026-08-18 08:13'
updated_date: '2026-08-18 10:18'
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
- [x] #1 Architect design ratified: the exempt-path mechanism, its checked-in list, and the ancestor-walk rule in the preflight
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

author: foreman
created: 2026-08-18 10:08
---
KING RATIFIED the doc-030 design, 2026-08-18, in the foreman's console: "STATBUS-219 Approved". AC#1 closed. Stage 1 (preflight-side ride) dispatched to the engineer; Stage 2 stays gated on the all-jobs-skipped conclusion probe per the design.
---

author: engineer
created: 2026-08-18 10:18
---
**STAGE 1 BUILT to doc-030, frozen for review (no commit).** Preflight-side only — zero workflow/trigger changes, so AC#2 remains Stage 2's, gated on the all-jobs-skipped probe. This unit closes AC#3, AC#4, AC#5.

**Files:** new `ops/release/ci-exempt-paths.txt` (one entry: `.backlog/`), `cli/cmd/release.go` (+288/-15), new `cli/cmd/release_ci_exempt_ride_test.go`.

**The mechanism** — `ciExemptPathsFile` :1365, `ciExemptRideWalkBound = 50` :1371, `loadCIExemptPaths` :1376, `fileIsCIExempt` :1410, `changedFilesAllExempt` :1438, `exemptRide` :1455, `findExemptRide` :1483, `printExemptRide` :1557. Wired at the two verdict-gate sites only: pg_regress :199 and `checkPrereleaseWorkflowGate` :624 (which serves go-test, app-build-lint, fast-tests). The walk reuses the STATBUS-216 seam vars, so every arm is pinned offline against real git fixtures.

**THE INVERSION, as warned.** `fileIsCIExempt` is a separate helper whose comment states the inversion in full and names `diffTouchesSensitivePath` as the thing NOT to copy. Anchored prefix: `.backlog/` matches `.backlog/tasks/x.md`, never `vendor/.backlog/thing.md`; an entry without a trailing slash matches that exact file or that directory's contents, so a future `doc` entry can never exempt `docker-compose.yml`. **RED-verified**: swapping the helper to `strings.Contains` turns four cases red immediately.

**IMAGES NEVER RIDES** — reason recorded in code at release.go:476 (a question about the world, not the code), citing workflow_check.go:104-107 and the fast-tests pull coupling. `TestImagesGateNeverRides` fails if `findExemptRide` ever appears in the images gate's span or if the reason text is deleted.

**Refusal arms, each test-pinned:** non-exempt file in the diff (names the offender); exempt-clean ancestors but none green; missing/unreadable exempt list (fails CLOSED, names the file); walk bound (never probes more than 50); Unknown never attempts the ride. Plus gate-level `TestPrereleaseGate_RidesAndRefusesLoudly` — rides loudly naming the tested commit and every justifying file; refuses loudly with "No exempt-only ancestor ride available: …".

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `gofmt -l` clean. `golangci-lint run ./...` at 2.12.2 — 0 issues (it first found 3 `ineffassign` in my new test file — the 213 class — fixed before freezing; the gofmt step and the lint step each caught something the other did not).

Six points doc-030 left open, which I resolved, are in the next comment — flagged separately so the architect can rule on each.
---

author: engineer
created: 2026-08-18 10:18
---
**SIX POINTS doc-030 LEFT OPEN THAT I RESOLVED — flagged, not buried. Each is cheap to reverse; the architect should rule.**

**1. The walk does NOT stop at the first non-exempt candidate.** My brief's phrasing ("non-exempt diff … refuses") reads as stop-on-first, but doc-030's own add-then-revert rationale requires the opposite: a direct diff compares TREES, so an older ancestor can be tree-identical to the tip even when a nearer one differs. Stopping early would discard exactly the ride the direct-diff design exists to find. I continue to the bound; only exempt-clean candidates cost an API call, so a non-exempt candidate costs one local `git diff`. Pinned by `TestFindExemptRide_AddThenRevertRidesTheOlderAncestor`.

**2. pg_regress rides too, and its stamp is NOT persisted.** doc-030's table lists pg_regress as a verdict gate, but its call site has a shape the other three do not: on green it writes `tmp/fast-test-passed-sha`, and later checks diff `stampSHA..HEAD` for migration and `test/expected/` drift. On a ride I feed those checks the RIDE TARGET's SHA — the truthful claim — so they verify ACROSS the ride span on their own (empty by construction, since `migrations/` and `test/` are not exempt; no special-casing). I deliberately do NOT write the stamp to disk: a stamp records that a suite RAN at a SHA; a ride is an inference re-derived in under a second every invocation. Persisting it would let a later reader — or a later code path — mistake inference for evidence, and would outlive the ancestor green that justified it.

**3. Unknown never rides.** doc-030 names Missing/Pending/Failed; Unknown is unlisted. Excluded deliberately: an unreachable API cannot verify an ancestor either, and that refusal is about the check, not the code. Pinned by asserting the walk is not even entered (exactly one probe).

**4. A missing or unreadable exempt list fails CLOSED.** Not specified. No list ⇒ no ride, and the refusal names the file.

**5. Git-quoted paths are never exempt.** `git diff --name-only` quotes paths containing non-ASCII or special characters (`"\303\251…"`). Such a path begins with a quote and matches no anchored prefix, so it lands on the safe side — the under-inclusive direction. Documented in both the helper and the list header, pinned by a case.

**6. The refusal reports BOTH facts when both were observed** — "the exempt-only ancestors have no green run, AND older ones differ in non-exempt files (e.g. X)". I found this because a test of mine initially asserted the wrong message: they are different operator problems. "Exempt-clean but ungreen" means waiting or re-running fixes it; "non-exempt file" means this code state is genuinely untested and no waiting will change that.

**Also not done, deliberately:** the images gate still calls `release.CheckWorkflowAtCommit` directly rather than the STATBUS-216 seam. It must never ride, so there is nothing to stub, and converting it would only blur the exclusion the `TestImagesGateNeverRides` pin protects.

**Note for Stage 2's probe:** nothing in Stage 1 depends on the all-jobs-skipped conclusion. If the probe returns `success`, the ride still fires correctly — a phantom-green run at the tip would be read as Green and the gate passes without the ride at all, which is the softness 199/215 already refuse elsewhere and NOT something Stage 1 can or should compensate for.
---
<!-- COMMENTS:END -->
