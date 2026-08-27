---
id: STATBUS-276
title: >-
  drift-oracle-escape: the preflight's drift refusals consult CI before refusing
  — a stale stamp no longer demands a local duplicate of a run CI already proved
status: Done
assignee:
  - engineer
created_date: '2026-08-27 14:41'
updated_date: '2026-08-27 14:55'
labels:
  - release
dependencies: []
priority: high
type: enhancement
ordinal: 269000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King's ruling at the rc.10 cut (2026-08-27): with fast-tests GREEN at the exact tip, the preflight's stamp-drift check still demanded a local run — "it shouldn't be required if our automation works the way it was supposed to." Architect's history read: the CI-fallback (task #129) fires only when NO local stamp exists; the stale-stamp path never consults CI — incomplete generalisation, not a reasoned boundary. The correctness argument, stated as a decision: the drift check guards environment-dependent baselines (explain/performance), and for those CI is the REFERENCE environment a release is cut for — the local machine is the weaker oracle.

The fix (architect-designed, engineer-built): at both drift-refusal sites, consult checkWorkflowAtCommit(WorkflowPgRegress, HEAD) immediately before refusing — green passes by construction (CI ran pg_regress against this committed tree) and refreshes the stamp; anything else refuses verbatim as today. Ride path untouched (persist distinction preserved). STILL REFUSES: stale stamp AND no CI green — the genuinely unverified case.

Recorded limits, from the architect's second ruling: (1) justified by construction only — the local-template divergence stays out of the argument (undiagnosed; could be a test defect CI masks); (2) this does NOT lift any red test — the 105 divergence needs its own diagnosis regardless; (3) landing this SPENDS the current tip's green (fresh fast-tests round needed at the fix commit) — accepted because it ends the toll permanently.

WHAT IS ACHIEVED: a green CI run at the committed tree is honoured as the proof it is, on every future cut; only the genuinely unverified case still refuses.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-27 14:42
---
**BUILT, FULL CHAIN GREEN, RED-VERIFIED, FROZEN.** Three files:

- `cli/cmd/release.go` — **14 insertions, 3 deletions**, the entire tracked-file diff
- `cli/cmd/release_drift_ci_escape.go` (new) — the escape
- `cli/cmd/release_drift_ci_escape_test.go` (new) — the tests

Chain: `go build ./...`, `go vet ./...`, `gofmt -l` clean; **full `go test ./...` green** (`cmd` 78.5s, every package ok).

## Built as ruled

Both refusal sites consult `checkWorkflowAtCommit(release.WorkflowPgRegress, headFull)` immediately before refusing (release.go:338 expected-files, :354 new-migrations outer condition). Green passes with the by-construction line and refreshes the stamp; anything else falls through to **today's refusal verbatim** — not a byte of either refusal body changed. The ride path's synthesized non-persisted `stampBytes` is untouched; the single addition there is `stampFromRide = true` (:223), a flag declared at :186 whose only job is to carry the ride's do-not-persist property to the one place that would otherwise write a stamp. Refresh matches the CI-green branch's two-line content and best-effort handling. Still refuses on stale stamp AND no CI green.

## The three recorded limits are honoured in the code, not just in intent

The comment argues **by construction only**: CI checked out this committed tree and ran the suite against it, so whatever drifted between the stamp's SHA and HEAD was exercised there; these baselines drift per environment and CI is the reference environment a release is cut for. The local-template divergence appears nowhere. And the comment carries an explicit **WHAT THIS DOES NOT DO** paragraph — it applies only where a gate is ALREADY satisfied, a red or missing pg_regress refuses here exactly as it refuses everywhere else, nothing lets a failing test through.

## A real defect, caught by the zero-scope arm rather than by review

My first version treated an empty `headFull` as the no-HEAD case. `upgrade.RunCommandOutput` returns `CombinedOutput` (cli/internal/upgrade/exec.go:52-66), so a failed `git rev-parse` hands back git's own message as the OUTPUT: `headFull` became `"fatal: not a"`, non-empty, and the escape sailed past the guard and **claimed coverage at a commit that does not exist**. A gate relaxation failing OPEN on its own confusion is the worst shape this could have had. It now checks the error rather than the emptiness, with the reason recorded at the line and named to the test that caught it. The same `headOut, _ :=` idiom at release.go:185 is SAFE — a garbage SHA there yields Missing and refuses — so it is not a latent bug and I left it untouched.

## RED-verified — four mutations, each site asserted

Harness `tmp/red_verify_drift_escape.sh`, log `tmp/red_verify_drift_escape.log`. Because this is a gate RELAXATION, every mutation targets the direction it must still KEEP:

- escape fires on ANY status → the failed/pending/missing/unknown arms break
- ride path persists its inferred stamp → the ride arm breaks
- escape path stops refreshing → the stamp-content arm breaks
- error check removed → the no-HEAD arm breaks

Restored byte-identical afterwards.

## Two items flagged for the architect's review

**1. One line changed outside the sites the design named — offered for veto.** release.go:182 now reads `stampPath := fastTestStampPath(projDir)`, a pure one-line extraction, no control flow touched, well outside the untouchable :205-218. Reason: the escape is now a second reader/writer of that path, and two hand-built copies drifting apart would fail open silently. Reverting to a duplicated literal is a one-minute change.

**2. A boundary stated rather than papered over.** The tests pin the escape's VERDICT through the `checkWorkflowAtCommit` seam — asserting the function's boolean, not what the live API happens to answer. They do NOT pin the two call sites' POLARITY: a dropped `!` would invert the gate and no unit test would catch it, because `preflightChecks` is not unit-testable end to end. That is the same coverage every other gate in that function has, so it is not a regression — but it is the one property review has to carry.

No git operations. `cli/cmd/release.go` modified; the two escape files untracked.
---

author: architect (pinned by foreman)
created: 2026-08-27 14:43
---
VERDICT: LAND (2026-08-27). Polarity verified AT SOURCE at both sites — :338 and :354 read `} else if !driftCoveredByCIGreen(…) {`, branch BODIES checked not just conditions (each opens with its ✗ refusal, preceding arm carries the ✓): the sense is refuse-when-NOT-covered, correct; the dropped-! inversion is absent. The :182 extraction RATIFIED, not vetoed: a path literal duplicated between reader and writer is a textbook silent-divergence bug whose failure mode here is FAIL-OPEN (the escape writes a stamp nobody reads, the toll recurs silently) — duplicating the literal would optimise for a smaller diff at the cost of a silent hazard inside a gate.

STANDING PRINCIPLE from the engineer's self-caught v1 defect (failed rev-parse yields CombinedOutput error text → non-empty → coverage claimed at a nonexistent commit): A RELAXATION MUST VALIDATE ITS INPUTS MORE STRICTLY THAN THE GUARD IT BYPASSES — a confused guard refuses and someone investigates; a confused relaxation GRANTS and nobody hears anything. They are not symmetric and cannot share a standard of care. Corollary judged sharper than consistency: the same idiom at :185 is safe (garbage SHA → Missing → refuses, self-limiting confusion) and was correctly left alone — change only the dangerous position.

LANDING HELD until: the King's local fast-suite run completes, its dirtied baselines are dispositioned per testing rules (discard trivial drift, flag suspicious), and the 105 divergence has its diagnosis — the escape lands regardless of 105's outcome but never carries us past an unexplained red.
---

author: foreman
created: 2026-08-27 14:55
---
LANDED at 1541189e6 (throwaway-worktree build+vet+tests green). The mechanic's independent point-by-point verification (crossed dispatch, converted to a second full-chain review) is part of the landing record — tmp/agents/mechanic.md. EMPIRICAL GROUNDING arrived the same hour and is pinned here deliberately: the King's local fast-suite run at the same commit produced PAGE-ALIGNED NUL corruption in two bind-mount-written artifacts (one contiguous 4096-aligned hole per file, every differing byte NUL, surroundings byte-identical to HEAD — byte-level proof in the 105 investigation) while CI passed the same tree. On this development machine the local runner is demonstrably the weaker oracle for container-crossing artifacts — the design's stated decision, proven by the incident that motivated it. The corrupted tracked file was restored losslessly; the failing run correctly wrote NO stamp (the gate held even while its artifact was being corrupted).
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The preflight's drift refusals consult CI before demanding a local duplicate. Both refusal sites check the pg_regress workflow at HEAD: green passes by construction and refreshes the stamp; a stale stamp with no CI green refuses exactly as before; the ride path's persist distinction is untouched. Landed at 1541189e6 after architect review (polarity verified at source in both branch bodies; the shared-path extraction ratified as removing a fail-open divergence hazard). Standing principle recorded from the build's self-caught defect: a relaxation must validate its inputs more strictly than the guard it bypasses — its failure mode is permission, not refusal. Empirically grounded the same hour: the local machine corrupted two run artifacts with page-aligned NUL holes while CI passed the identical tree — CI is the reference environment, now honoured as such on every future cut.
<!-- SECTION:FINAL_SUMMARY:END -->
